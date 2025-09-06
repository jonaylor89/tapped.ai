#!/bin/bash

# Directory containing JSON files
DIRECTORY="./storage/datasets/default"

# Loop through all JSON files in the directory
find "$DIRECTORY" -type f -name "*.json" | while read FILE; do
  # Check if the file is a valid JSON
  if ! jq empty "$FILE" > /dev/null 2>&1; then
    echo "Corrupt JSON file: $FILE"
  fi
done
