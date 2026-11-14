# ============================================================
# run_pipeline.ps1
# Full pipeline runner for NYC EV Mobility Data Warehouse
# Usage: just run this file in PowerShell
# ============================================================

$PSQL    = "C:\Program Files\PostgreSQL\17\bin\psql.exe"
$DB      = "nyc_ev_mobility_dw"
$USER    = "postgres"
$PASS    = "1250"
$BASE    = $PSScriptRoot   # folder where this script lives

# Set password so psql never prompts
$env:PGPASSWORD = $PASS

function Run-SQL {
    param([string]$label, [string]$file)
    Write-Host "`n>>> $label" -ForegroundColor Cyan
    # ON_ERROR_STOP makes psql return a non-zero exit code when any statement fails
    & $PSQL -U $USER -d $DB -v ON_ERROR_STOP=1 -f $file
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR in $label — stopping." -ForegroundColor Red
        exit 1
    }
    Write-Host "    Done." -ForegroundColor Green
}

function Run-Python {
    param([string]$label, [string]$file)
    Write-Host "`n>>> $label" -ForegroundColor Cyan
    python $file
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR in $label — stopping." -ForegroundColor Red
        exit 1
    }
    Write-Host "    Done." -ForegroundColor Green
}

# ── STEP 1: Create database if it doesn't exist ─────────────
Write-Host "`n>>> Creating database $DB (safe to ignore 'already exists' error)" -ForegroundColor Cyan
& $PSQL -U $USER -c "CREATE DATABASE $DB ENCODING 'UTF8' TEMPLATE template0;" 2>&1 | Out-Null
Write-Host "    Done." -ForegroundColor Green

# ── STEP 2: Schemas ─────────────────────────────────────────
Run-SQL "Create Schemas" "$BASE\sql\01_setup\01_create_schemas.sql"

# ── STEP 3: Staging tables ───────────────────────────────────
Run-SQL "Create Staging Tables" "$BASE\sql\02_staging\01_create_staging_tables.sql"

# ── STEP 4: Load CSVs into staging via Python ───────────────
Run-Python "Loading CSVs into staging (Python)" "$BASE\python\load_staging.py"

# ── STEP 5: Clean views ──────────────────────────────────────
Run-SQL "Create Clean Staging Views" "$BASE\sql\02_staging\02_clean_staging.sql"

# ── STEP 6: Dimension tables ─────────────────────────────────
Run-SQL "Create Dimension Tables" "$BASE\sql\03_dimensions\01_create_dimensions.sql"

# ── STEP 7: Load dimensions from staging ────────────────────
Run-SQL "Load Dimensions (ETL)" "$BASE\sql\05_etl\01_load_dimensions.sql"

# ── STEP 8: Fact tables (must come AFTER dimensions are created) ──
Run-SQL "Create Fact Tables" "$BASE\sql\04_facts\01_create_facts.sql"

# ── STEP 9: Map EV stations to taxi zones (spatial join) ────
Run-Python "Mapping EV stations to taxi zones (Python)" "$BASE\python\assign_stations_to_zones.py"

# ── STEP 10: Load facts (business key -> surrogate key) ─────
Run-SQL "Load Facts (ETL)" "$BASE\sql\05_etl\02_load_facts.sql"

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "  Done! Dimensions and fact tables loaded." -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Green
