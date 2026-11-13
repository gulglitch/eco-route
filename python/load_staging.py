"""
load_staging.py
---------------
Loads all 4 raw CSV files into the project_staging schema in PostgreSQL.

Requirements:
    pip install psycopg2-binary pandas

Usage:
    python load_staging.py

Make sure PostgreSQL is running and the schemas + staging tables already exist.
Run these first in pgAdmin:
    1. sql/01_setup/01_create_schemas.sql
    2. sql/02_staging/01_create_staging_tables.sql
"""

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from datetime import datetime
import os

# ─────────────────────────────────────────────
# DATABASE CONNECTION — change password if needed
# ─────────────────────────────────────────────
DB_CONFIG = {
    'host': '127.0.0.1',   # explicit IPv4 — avoids IPv6 ::1 issues
    'port': 5432,
    'database': 'nyc_ev_mobility_dw',
    'user': 'postgres',
    'password': '1250'
}

# Path to raw data folder (relative to this script's location)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RAW_DIR  = os.path.join(BASE_DIR, '..', 'data', 'raw')

BATCH_ID = datetime.now().strftime('BATCH_%Y%m%d_%H%M%S')


# ─────────────────────────────────────────────
# HELPER
# ─────────────────────────────────────────────
def get_connection():
    return psycopg2.connect(**DB_CONFIG)


def truncate_table(conn, schema, table):
    with conn.cursor() as cur:
        cur.execute(f"TRUNCATE TABLE {schema}.{table} RESTART IDENTITY CASCADE;")
    conn.commit()
    print(f"  ✓ Truncated {schema}.{table}")


# ─────────────────────────────────────────────
# 1. LOAD TRIPS
# ─────────────────────────────────────────────
def clean_val(x):
    """Convert NaN, NaT, and pandas NA to Python None for psycopg2."""
    if x is None:
        return None
    try:
        if pd.isnull(x):
            return None
    except (TypeError, ValueError):
        pass
    return x


def load_trips(conn):
    filepath = os.path.join(RAW_DIR, 'nyc_fhv_trips_jan2024.csv')
    print(f"\n[1/4] Loading trips from {filepath} ...")

    # Read all columns as strings first — avoids NaT/NaN type issues
    df = pd.read_csv(filepath, dtype=str, low_memory=False)

    # Lowercase column names
    df.columns = [c.lower() for c in df.columns]

    # Datetime columns: convert empty/NaN strings to None, valid ones to datetime
    dt_cols = ['request_datetime', 'on_scene_datetime', 'pickup_datetime', 'dropoff_datetime']
    for col in dt_cols:
        df[col] = pd.to_datetime(df[col], errors='coerce')
        df[col] = df[col].apply(lambda x: None if pd.isnull(x) else x.to_pydatetime())

    # Numeric columns: cast to float, replace NaN with None
    num_cols = ['pulocationid', 'dolocationid', 'trip_miles', 'trip_time',
                'base_passenger_fare', 'tolls', 'bcf', 'sales_tax',
                'congestion_surcharge', 'airport_fee', 'tips', 'driver_pay']
    for col in num_cols:
        df[col] = pd.to_numeric(df[col], errors='coerce')
        df[col] = df[col].apply(lambda x: None if pd.isnull(x) else x)

    # String columns: replace empty/NaN with None
    str_cols = ['hvfhs_license_num', 'dispatching_base_num', 'originating_base_num',
                'shared_request_flag', 'shared_match_flag', 'access_a_ride_flag',
                'wav_request_flag', 'wav_match_flag']
    for col in str_cols:
        df[col] = df[col].apply(lambda x: None if (pd.isnull(x) or str(x).strip() == '') else str(x).strip())

    # Add audit columns
    df['load_timestamp'] = datetime.now()
    df['batch_id']       = BATCH_ID
    df['source_file']    = 'nyc_fhv_trips_jan2024.csv'

    cols = [
        'hvfhs_license_num', 'dispatching_base_num', 'originating_base_num',
        'request_datetime', 'on_scene_datetime', 'pickup_datetime', 'dropoff_datetime',
        'pulocationid', 'dolocationid', 'trip_miles', 'trip_time',
        'base_passenger_fare', 'tolls', 'bcf', 'sales_tax',
        'congestion_surcharge', 'airport_fee', 'tips', 'driver_pay',
        'shared_request_flag', 'shared_match_flag', 'access_a_ride_flag',
        'wav_request_flag', 'wav_match_flag',
        'load_timestamp', 'batch_id', 'source_file'
    ]

    truncate_table(conn, 'project_staging', 'stg_trips')

    # Build rows — apply clean_val to every cell as final safety net
    rows = [
        tuple(clean_val(x) for x in row)
        for row in df[cols].itertuples(index=False, name=None)
    ]

    with conn.cursor() as cur:
        execute_values(
            cur,
            f"""INSERT INTO project_staging.stg_trips ({', '.join(cols)}) VALUES %s""",
            rows,
            page_size=5000
        )
    conn.commit()
    print(f"  ✓ Loaded {len(df):,} trip rows")


# ─────────────────────────────────────────────
# 2. LOAD WEATHER
# ─────────────────────────────────────────────
def load_weather(conn):
    filepath = os.path.join(RAW_DIR, 'nyc_weather_jan2024.csv')
    print(f"\n[2/4] Loading weather from {filepath} ...")

    df = pd.read_csv(filepath, parse_dates=['datetime'])
    df = df.where(pd.notnull(df), None)

    df['load_timestamp'] = datetime.now()
    df['batch_id']       = BATCH_ID
    df['source_file']    = 'nyc_weather_jan2024.csv'

    cols = ['datetime', 'precipitation_mm', 'temperature_c', 'humidity_percent',
            'load_timestamp', 'batch_id', 'source_file']

    truncate_table(conn, 'project_staging', 'stg_weather')

    rows = [tuple(row) for row in df[cols].itertuples(index=False, name=None)]

    with conn.cursor() as cur:
        execute_values(
            cur,
            f"""INSERT INTO project_staging.stg_weather ({', '.join(cols)}) VALUES %s""",
            rows
        )
    conn.commit()
    print(f"  ✓ Loaded {len(df):,} weather rows")


# ─────────────────────────────────────────────
# 3. LOAD ZONES
# ─────────────────────────────────────────────
def load_zones(conn):
    filepath = os.path.join(RAW_DIR, 'taxi+_zone_lookup (1).csv')
    print(f"\n[3/4] Loading zones from {filepath} ...")

    df = pd.read_csv(filepath)
    df.columns = [c.strip().lower() for c in df.columns]
    df = df.where(pd.notnull(df), None)

    df['load_timestamp'] = datetime.now()
    df['batch_id']       = BATCH_ID
    df['source_file']    = 'taxi+_zone_lookup (1).csv'

    cols = ['locationid', 'borough', 'zone', 'service_zone',
            'load_timestamp', 'batch_id', 'source_file']

    truncate_table(conn, 'project_staging', 'stg_zones')

    rows = [tuple(row) for row in df[cols].itertuples(index=False, name=None)]

    with conn.cursor() as cur:
        execute_values(
            cur,
            f"""INSERT INTO project_staging.stg_zones ({', '.join(cols)}) VALUES %s""",
            rows
        )
    conn.commit()
    print(f"  ✓ Loaded {len(df):,} zone rows")


# ─────────────────────────────────────────────
# 4. LOAD EV CHARGING STATIONS
# ─────────────────────────────────────────────
def load_charging_stations(conn):
    filepath = os.path.join(RAW_DIR, 'Electric_Vehicle_Charging_Stations_in_New_York.csv')
    print(f"\n[4/4] Loading EV stations from {filepath} ...")

    df = pd.read_csv(filepath, low_memory=False)

    # Rename columns from CSV headers to staging table column names
    rename_map = {
        'ID'                    : 'station_id',
        'Station Name'          : 'station_name',
        'Street Address'        : 'street_address',
        'City'                  : 'city',
        'State'                 : 'state',
        'ZIP'                   : 'zip',
        'Latitude'              : 'latitude',
        'Longitude'             : 'longitude',
        'EV Network'            : 'ev_network',
        'EV Connector Types'    : 'ev_connector_types',
        'EV Level1 EVSE Num'    : 'ev_level1_evse_num',
        'EV Level2 EVSE Num'    : 'ev_level2_evse_num',
        'EV DC Fast Count'      : 'ev_dc_fast_num',
        'Status Code'           : 'status_code',
        'Open Date'             : 'open_date',
        'Date Last Confirmed'   : 'date_last_confirmed',
        'Fuel Type Code'        : 'fuel_type_code',
        'Intersection Directions': 'intersection_directions',
        'Groups With Access Code': 'access_code',
        'Facility Type'         : 'facility_type',
    }
    df.rename(columns=rename_map, inplace=True)

    # Parse date columns — explicitly convert NaT to Python None
    for date_col in ['open_date', 'date_last_confirmed']:
        if date_col in df.columns:
            df[date_col] = pd.to_datetime(df[date_col], errors='coerce')
            df[date_col] = df[date_col].apply(lambda x: None if pd.isnull(x) else x.date())

    # Numeric columns — replace NaN with None
    num_cols = ['latitude', 'longitude', 'ev_level1_evse_num', 'ev_level2_evse_num', 'ev_dc_fast_num']
    for col in num_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')
            df[col] = df[col].apply(lambda x: None if pd.isnull(x) else x)

    # String columns — replace NaN with None
    str_cols = ['station_id', 'station_name', 'street_address', 'city', 'state', 'zip',
                'ev_network', 'ev_connector_types', 'status_code', 'fuel_type_code',
                'intersection_directions', 'access_code', 'facility_type']
    for col in str_cols:
        if col in df.columns:
            df[col] = df[col].apply(lambda x: None if (pd.isnull(x) or str(x).strip() == '') else str(x).strip())

    df['load_timestamp'] = datetime.now()
    df['batch_id']       = BATCH_ID
    df['source_file']    = 'Electric_Vehicle_Charging_Stations_in_New_York.csv'

    cols = [
        'station_id', 'station_name', 'street_address', 'city', 'state', 'zip',
        'latitude', 'longitude', 'ev_network', 'ev_connector_types',
        'ev_level1_evse_num', 'ev_level2_evse_num', 'ev_dc_fast_num',
        'status_code', 'open_date', 'date_last_confirmed',
        'fuel_type_code', 'intersection_directions', 'access_code', 'facility_type',
        'load_timestamp', 'batch_id', 'source_file'
    ]

    # Keep only columns that exist in the dataframe
    cols = [c for c in cols if c in df.columns]

    truncate_table(conn, 'project_staging', 'stg_charging_stations')

    rows = [
        tuple(clean_val(x) for x in row)
        for row in df[cols].itertuples(index=False, name=None)
    ]

    with conn.cursor() as cur:
        execute_values(
            cur,
            f"""INSERT INTO project_staging.stg_charging_stations ({', '.join(cols)}) VALUES %s""",
            rows,
            page_size=1000
        )
    conn.commit()
    print(f"  ✓ Loaded {len(df):,} EV station rows")


# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
if __name__ == '__main__':
    print("=" * 55)
    print("  NYC EV Mobility DW — Staging Loader")
    print(f"  Batch: {BATCH_ID}")
    print("=" * 55)

    conn = get_connection()
    try:
        load_trips(conn)
        load_weather(conn)
        load_zones(conn)
        load_charging_stations(conn)
        print("\n✅ All staging tables loaded successfully!")
    except Exception as e:
        conn.rollback()
        print(f"\n❌ Error: {e}")
        raise
    finally:
        conn.close()
