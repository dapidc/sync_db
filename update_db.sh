#!/bin/bash

# This script updates the database with the latest changes
# Check if the database update command is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <update_command>"
  exit 1
fi