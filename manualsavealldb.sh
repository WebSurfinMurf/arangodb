#!/bin/bash
################################################################################
# ArangoDB Manual WAL Flush/Checkpoint
################################################################################
# Location: /home/administrator/projects/arangodb/manualsavealldb.sh
#
# Purpose: Forces ArangoDB to flush WAL (Write-Ahead Log) to disk
# This ensures all data and operations are persisted before backup.
#
# Called by: backup scripts before creating tar archives
################################################################################

set -e

echo "=== ArangoDB: Forcing WAL flush and sync ==="

# Check if ArangoDB credentials are in secrets file
ARANGO_ROOT_PASSWORD=""
if [ -f /home/administrator/secrets/arangodb.env ]; then
    source /home/administrator/secrets/arangodb.env 2>/dev/null
fi

# Try alternative variable names
if [ -z "$ARANGO_ROOT_PASSWORD" ] && [ -n "$ARANGODB_ROOT_PASSWORD" ]; then
    ARANGO_ROOT_PASSWORD="$ARANGODB_ROOT_PASSWORD"
fi

# Build authentication parameter
if [ -n "$ARANGO_ROOT_PASSWORD" ]; then
    AUTH_PARAM="--server.password=$ARANGO_ROOT_PASSWORD"
    echo "Using authenticated connection"
else
    AUTH_PARAM=""
    echo "Using non-authenticated connection"
fi

# Flush WAL to disk
echo "Flushing Write-Ahead Log (WAL) to disk..."
FLUSH_RESULT=$(docker exec arangodb arangosh $AUTH_PARAM \
    --server.endpoint=tcp://127.0.0.1:8529 \
    --javascript.execute-string='require("internal").wal.flush(true, true);' 2>&1)

if [ $? -eq 0 ]; then
    echo "✓ ArangoDB WAL flush completed successfully"
else
    echo "✗ ArangoDB WAL flush failed"
    echo "$FLUSH_RESULT"
    exit 1
fi

# Get database statistics
echo ""
echo "Checking database status..."
STATS=$(docker exec arangodb arangosh $AUTH_PARAM \
    --server.endpoint=tcp://127.0.0.1:8529 \
    --javascript.execute-string='
        var dbs = db._databases();
        print("Databases: " + dbs.length);
        dbs.forEach(function(dbName) {
            db._useDatabase(dbName);
            var colls = db._collections().filter(c => !c.name().startsWith("_"));
            print("  - " + dbName + ": " + colls.length + " collections");
        });
    ' 2>/dev/null | grep -E "Databases:|  -")

echo "$STATS"

echo ""
echo "✓ All ArangoDB data has been flushed to disk"
echo "  Write-Ahead Log synced"
echo "  All databases are in consistent state for backup"

echo ""
echo "=== ArangoDB save operation complete ==="
