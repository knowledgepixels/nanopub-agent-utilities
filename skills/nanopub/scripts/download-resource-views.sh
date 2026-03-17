#!/usr/bin/env bash
# Download all resource view nanopublications from Nanopub Query
# and store them as individual TriG files in the resource-views/ subfolder.
#
# Usage: ./download-resource-views.sh [output-dir]
#   output-dir defaults to the resource-views/ directory next to this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/../resource-views}"

mkdir -p "$OUTPUT_DIR"

echo "Fetching resource view list from Nanopub Query..."
QUERY_LIST=$(curl -s "https://query.knowledgepixels.com/api/RAcyg9La3L2Xuig-jEXicmdmEgUGYfHda6Au1Pfq64hR0/get-all-resource-views")

# Skip the CSV header line
TOTAL=$(echo "$QUERY_LIST" | tail -n +2 | wc -l)
echo "Found $TOTAL resource views."

COUNT=0
echo "$QUERY_LIST" | tail -n +2 | while IFS=, read -r _view view_label _viewKind _type _query _template_count _first_template _first_template_label _date np _rest; do
  # Extract the trusty ID from the nanopub URI
  TRUSTY_ID=$(echo "$np" | sed 's|.*/||')
  # Use view_label if available, otherwise fall back to trusty ID
  if [ -n "$view_label" ]; then
    # Sanitize label for filename: lowercase, replace spaces/special chars with hyphens
    FILENAME=$(echo "$view_label" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    OUTFILE="${OUTPUT_DIR}/${TRUSTY_ID}_${FILENAME}.trig"
  else
    OUTFILE="${OUTPUT_DIR}/${TRUSTY_ID}.trig"
  fi

  if [ -f "$OUTFILE" ]; then
    COUNT=$((COUNT + 1))
    echo "[$COUNT/$TOTAL] Skipping (exists): ${view_label:-$TRUSTY_ID}"
    continue
  fi

  COUNT=$((COUNT + 1))
  echo "[$COUNT/$TOTAL] Downloading: ${view_label:-$TRUSTY_ID}"
  curl -s -L -H "Accept: application/trig" "$np" -o "$OUTFILE"
done

echo "Done. Resource views stored in: $OUTPUT_DIR"
