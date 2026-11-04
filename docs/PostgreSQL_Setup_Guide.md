# PostgreSQL Setup Guide - NYC EV Mobility Data Warehouse

## Database Configuration

**Database Name:** `nyc_ev_mobility_dw`  
**PostgreSQL Version:** 12+ recommended  
**Character Encoding:** UTF8  
**Collation:** English_United States.1252 (or default)

---

## pgAdmin Setup Instructions

### Step 1: Create Database

1. Open **pgAdmin 4**
2. Connect to your PostgreSQL server (usually `localhost`)
3. Right-click on **Databases** → **Create** → **Database**
4. Enter database details:
   - **Database:** `nyc_ev_mobility_dw`
   - **Owner:** postgres (or your username)
   - **Encoding:** UTF8
   - **Template:** template0
   - **Connection Limit:** -1 (unlimited)
5. Click **Save**

### Step 2: Open Query Tool

1. Click on the newly created database `nyc_ev_mobility_dw`
2. Click **Tools** → **Query Tool** (or press Alt+Shift+Q)
3. You're now ready to run SQL scripts

### Step 3: Run Schema Creation Scripts

Execute the SQL scripts in this order:

1. **01_create_schemas.sql** - Creates the 3-layer architecture
2. **02_create_staging_tables.sql** - Creates staging tables

---

## Schema Architecture

```
nyc_ev_mobility_dw
│
├── project_staging (Bronze Layer)
│   ├── stg_trips
│   ├── stg_weather
│   ├── stg_zones
│   └── stg_charging_stations
│
├── project_dw (Silver Layer - Data Warehouse)
│   ├── Dimensions (to be created by other team members)
│   └── Facts (to be created by other team members)
│
└── project_reporting (Gold Layer - Data Marts)
    └── (to be created in Phase 3)
```

---

## Connection Details (for Python/ETL Scripts)

```python
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'nyc_ev_mobility_dw',
    'user': 'postgres',
    'password': 'your_password_here'
}
```

---

## Schema Purposes

### 1. project_staging
**Purpose:** Raw data landing zone  
**Characteristics:**
- No constraints (except NOT NULL on critical fields)
- Includes audit columns (load_timestamp, batch_id)
- Temporary storage for data quality checks
- 1:1 mapping with source files

### 2. project_dw
**Purpose:** Core data warehouse (dimensional model)  
**Characteristics:**
- Star schema design
- Surrogate keys on all dimensions
- Foreign key constraints
- SCD Type 1 and Type 2 support
- Optimized for analytics

### 3. project_reporting
**Purpose:** Business-friendly data marts  
**Characteristics:**
- Pre-aggregated tables
- Denormalized for performance
- Business terminology
- Fast query response

---

## Post-Setup Verification

Run this query to verify all schemas:

```sql
SELECT 
    schemaname,
    COUNT(*) as table_count
FROM pg_tables
WHERE schemaname IN ('project_staging', 'project_dw', 'project_reporting')
GROUP BY schemaname
ORDER BY schemaname;
```

Expected result after Task 2:
- project_staging: 5 tables
- project_dw: 0 tables (empty for now)
- project_reporting: 0 tables (empty for now)

---

## Common Issues & Solutions

### Issue 1: Permission Denied
**Error:** `permission denied for schema project_staging`  
**Solution:**
```sql
GRANT ALL ON SCHEMA project_staging TO your_username;
GRANT ALL ON SCHEMA project_dw TO your_username;
GRANT ALL ON SCHEMA project_reporting TO your_username;
```

### Issue 2: Schema Already Exists
**Error:** `schema "project_staging" already exists`  
**Solution:** Either:
- Drop and recreate: `DROP SCHEMA project_staging CASCADE;`
- Or skip schema creation and run table scripts only

### Issue 3: Cannot Connect from Python
**Solution:**
1. Check PostgreSQL is running
2. Verify pg_hba.conf allows local connections
3. Install psycopg2: `pip install psycopg2-binary`

---

## Next Steps After Setup

1. ✓ Create database and schemas
2. ⏭️ Load data into staging tables (Team Member 2)
3. ⏭️ Run data quality checks (Team Member 2)
4. ⏭️ Transform and load dimensions (Team Member 3)
5. ⏭️ Load fact tables (Team Member 4)
6. ⏭️ Create reporting marts (Team Member 5)
7. ⏭️ Build Power BI dashboards (Phase 3)

---

**Setup Time:** ~10 minutes  
**Ready for:** ETL Pipeline Implementation
