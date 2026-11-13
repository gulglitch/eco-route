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
    & $PSQL -U $USER -d $DB -f $file
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
Write-Host "`n>>> Loading CSVs into staging (Python)" -ForegroundColor Cyan
python "$BASE\python\load_staging.py"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR in Python loader — stopping." -ForegroundColor Red
    exit 1
}
Write-Host "    Done." -ForegroundColor Green

# ── STEP 5: Clean views ──────────────────────────────────────
Run-SQL "Create Clean Staging Views" "$BASE\sql\02_staging\02_clean_staging.sql"

# ── STEP 6: Dimension tables ─────────────────────────────────
Run-SQL "Create Dimension Tables" "$BASE\sql\03_dimensions\01_create_dimensions.sql"

# ── STEP 7: Load dimensions from staging ────────────────────
Run-SQL "Load Dimensions (ETL)" "$BASE\sql\05_etl\01_load_dimensions.sql"

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "  Done! All dimension tables loaded." -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Green
