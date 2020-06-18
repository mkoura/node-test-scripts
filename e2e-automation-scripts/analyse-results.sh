#!/bin/bash

failed_tests=()

input="tests-results.txt"
while IFS= read -r line; do
    echo "$line"
    if [[ $line != *"0"* ]]; then
        failed_tests+=("$line")
    fi
done < "$input"

# Left for debugging
# echo "Failed tests: ${failed_tests[@]}"

for test in "${failed_tests[@]}"; do
    echo "Failed test: ${test}"
done

if (( ${#failed_tests[@]} > 0 )); then
    exit 1
fi

exit 0
