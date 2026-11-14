"""
assign_stations_to_zones.py
---------------------------
Spatially assigns every EV charging station (project_dw.dim_station) to the NYC
taxi zone that contains it, using the TLC taxi-zone shapefile.

Result is written to project_staging.stg_station_zone_map, which
sql/05_etl/02_load_facts.sql uses to load fact_charger_coverage.

Requirements:
    pip install geopandas shapely pyproj psycopg2-binary pandas
    (geopandas >= 0.10 is needed for sjoin_nearest)

Usage (from the repo root or from /python):
    python python/assign_stations_to_zones.py
    python python/assign_stations_to_zones.py "path/to/taxi_zones.zip"   # optional

Run AFTER sql/05_etl/01_load_dimensions.sql (needs dim_station) and BEFORE
sql/05_etl/02_load_facts.sql.

Method
    1. Stations (WGS84 lat/lon) and zone polygons are both put in EPSG:2263
       (NY Long Island State Plane, units = feet) so distances are meaningful.
    2. Station-in-polygon match ("within").
    3. Stations that miss every polygon by a hair (shoreline/boundary points)
       are matched to the nearest zone if it is within ~300 m ("nearest").
    4. Everything else is outside NYC (upstate stations) and is not mapped.
    5. distance_to_zone_center_km = distance from the station to the zone centroid.
"""

import glob
import os
import sys
import tempfile
import zipfile
from datetime import datetime

import geopandas as gpd
import pandas as pd
import psycopg2
from psycopg2.extras import execute_values

from load_staging import DB_CONFIG   # reuse the same connection settings

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RAW_DIR = os.path.join(BASE_DIR, '..', 'data', 'raw')
BATCH_ID = datetime.now().strftime('MAP_%Y%m%d_%H%M%S')

PROJECTED_EPSG = 2263          # NAD83 / New York Long Island (ftUS)
FEET_TO_KM = 0.3048 / 1000
NEAREST_MAX_FEET = 1000        # ~300 m tolerance for boundary/shoreline points


def find_zone_zip():
    """Use the CLI argument if given, otherwise look for data/raw/taxi_zones*.zip."""
    if len(sys.argv) > 1:
        return sys.argv[1]
    matches = glob.glob(os.path.join(RAW_DIR, 'taxi_zones*.zip'))
    if not matches:
        sys.exit("ERROR: taxi zone shapefile zip not found in data/raw/. "
                 "Pass its path as an argument.")
    return matches[0]


def load_zone_polygons(zip_path):
    """Extract the shapefile zip, return one polygon per LocationID in EPSG:2263."""
    tmp_dir = tempfile.mkdtemp(prefix='taxi_zones_')
    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(tmp_dir)
    shp_files = glob.glob(os.path.join(tmp_dir, '**', '*.shp'), recursive=True)
    if not shp_files:
        sys.exit("ERROR: no .shp file found inside " + zip_path)

    zones = gpd.read_file(shp_files[0])
    if zones.crs is None:
        zones = zones.set_crs(epsg=PROJECTED_EPSG)
    zones = zones.to_crs(epsg=PROJECTED_EPSG)

    id_col = next(c for c in zones.columns if c.lower() == 'locationid')
    zones = zones[[id_col, 'geometry']].rename(columns={id_col: 'LocationID'})
    # Some LocationIDs appear on several polygons -> merge to one row per ID
    zones = zones.dissolve(by='LocationID').reset_index()
    zones['LocationID'] = zones['LocationID'].astype(int)
    return zones


def load_stations(conn):
    """Current dim_station rows that have coordinates."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT station_key, station_id, latitude, longitude
            FROM project_dw.dim_station
            WHERE is_current = TRUE
              AND latitude IS NOT NULL
              AND longitude IS NOT NULL
        """)
        rows = cur.fetchall()
    df = pd.DataFrame(rows, columns=['station_key', 'station_id', 'latitude', 'longitude'])
    df['latitude'] = df['latitude'].astype(float)
    df['longitude'] = df['longitude'].astype(float)
    return gpd.GeoDataFrame(
        df,
        geometry=gpd.points_from_xy(df['longitude'], df['latitude']),
        crs='EPSG:4326',
    ).to_crs(epsg=PROJECTED_EPSG)


def assign_zones(stations, zones):
    # 1) point-in-polygon
    within = gpd.sjoin(stations, zones, how='inner', predicate='within').drop(columns='index_right')
    within['match_method'] = 'within'

    # 2) near-miss fallback
    leftover = stations[~stations['station_key'].isin(within['station_key'])]
    parts = [within]
    if not leftover.empty:
        near = gpd.sjoin_nearest(leftover, zones, how='inner',
                                 max_distance=NEAREST_MAX_FEET).drop(columns='index_right')
        near = near.drop_duplicates(subset='station_key')
        near['match_method'] = 'nearest'
        parts.append(near)

    matched = gpd.GeoDataFrame(pd.concat(parts, ignore_index=True),
                               geometry='geometry', crs=zones.crs)

    # 3) distance to the centroid of the assigned zone
    centroids = zones.set_index('LocationID').geometry.centroid
    zone_centers = gpd.GeoSeries(centroids.loc[matched['LocationID']].values, crs=zones.crs)
    matched['distance_km'] = matched.geometry.distance(zone_centers, align=False) * FEET_TO_KM
    return matched


def write_map(conn, matched):
    with conn.cursor() as cur:
        cur.execute("DROP TABLE IF EXISTS project_staging.stg_station_zone_map;")
        cur.execute("""
            CREATE TABLE project_staging.stg_station_zone_map (
                station_key                 INTEGER PRIMARY KEY,
                station_id                  VARCHAR(100),
                location_id                 INTEGER NOT NULL,
                distance_to_zone_center_km  NUMERIC(10,4),
                match_method                VARCHAR(10),
                load_timestamp              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                batch_id                    VARCHAR(50)
            );
        """)
        cur.execute("""
            COMMENT ON TABLE project_staging.stg_station_zone_map IS
            'Derived: EV station -> taxi zone via spatial join (GeoPandas). Feeds fact_charger_coverage.';
        """)
        rows = [
            (int(r.station_key), r.station_id, int(r.LocationID),
             round(float(r.distance_km), 4), r.match_method, BATCH_ID)
            for r in matched.itertuples(index=False)
        ]
        execute_values(
            cur,
            """INSERT INTO project_staging.stg_station_zone_map
               (station_key, station_id, location_id, distance_to_zone_center_km,
                match_method, batch_id) VALUES %s""",
            rows,
        )
    conn.commit()


if __name__ == '__main__':
    print("=" * 55)
    print("  Station -> Taxi Zone spatial mapping")
    print(f"  Batch: {BATCH_ID}")
    print("=" * 55)

    zip_path = find_zone_zip()
    print(f"Zone shapefile : {zip_path}")

    conn = psycopg2.connect(**DB_CONFIG)
    try:
        zones = load_zone_polygons(zip_path)
        stations = load_stations(conn)
        print(f"Zones loaded   : {len(zones)}")
        print(f"Stations (with coordinates): {len(stations):,}")

        matched = assign_zones(stations, zones)
        write_map(conn, matched)

        n_within = int((matched['match_method'] == 'within').sum())
        n_near = int((matched['match_method'] == 'nearest').sum())
        print(f"  matched inside a zone       : {n_within:,}")
        print(f"  matched to nearest (<=300 m): {n_near:,}")
        print(f"  outside NYC (not mapped)    : {len(stations) - len(matched):,}")
        print("\n✅ project_staging.stg_station_zone_map loaded.")
    except Exception as e:
        conn.rollback()
        print(f"\n❌ Error: {e}")
        raise
    finally:
        conn.close()
