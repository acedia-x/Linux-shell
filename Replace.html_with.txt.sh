#!/bin/bash

for file in $(find /opt/data/ -type f -name "*.html"); do
    base="${file%.html}"
    mv "$file" "${base}.txt"
done

