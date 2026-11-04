-- ============================================================================
-- Script: 01_create_schemas.sql
-- Purpose: Create 3-layer warehouse architecture (Bronze → Silver → Gold)
-- Database: nyc_ev_mobility_dw
-- Phase: 2 - Physical Data Warehouse Implementation
-- ============================================================================

-- Drop schemas if they exist (use with caution in production!)
-- Uncomment the following lines if you want to recreate schemas
-- DROP SCHEMA IF EXISTS project_reporting CASCADE;
-- DROP SCHEMA IF EXISTS project_dw CASCADE;
-- DROP SCHEMA IF EXISTS project_staging CASCADE;

-- ============================================================================
-- Create Schemas
-- ============================================================================

-- BRONZE LAYER: Staging Schema (Raw Data Landing Zone)
CREATE SCHEMA IF NOT EXISTS project_staging;
COMMENT ON SCHEMA project_staging IS 
'Bronze Layer: Raw data from source systems. Minimal transformation. Includes audit columns.';

-- SILVER LAYER: Data Warehouse Schema (Dimensional Model)
CREATE SCHEMA IF NOT EXISTS project_dw;
COMMENT ON SCHEMA project_dw IS 
'Silver Layer: Core data warehouse with star schema. Dimensions and facts with surrogate keys and constraints.';

-- GOLD LAYER: Reporting Schema (Data Marts)
CREATE SCHEMA IF NOT EXISTS project_reporting;
COMMENT ON SCHEMA project_reporting IS 
'Gold Layer: Business-friendly data marts. Pre-aggregated and denormalized for analytics and reporting.';

-- ============================================================================
-- Verification Query
-- ============================================================================

SELECT 
    nspname AS schema_name,
    pg_catalog.obj_description(oid, 'pg_namespace') AS description
FROM pg_namespace
WHERE nspname IN ('project_staging', 'project_dw', 'project_reporting')
ORDER BY nspname;

-- ============================================================================
-- Expected Output:
-- project_dw         | Silver Layer: Core data warehouse...
-- project_reporting  | Gold Layer: Business-friendly data marts...
-- project_staging    | Bronze Layer: Raw data from source systems...
-- ============================================================================
