# Function to send ntfy notification
send_notification() {
    local message="$1"
    # Attempt curl with:
    # - max time of 5 seconds (-m 5)
    # - silent mode (-s)
    # - show errors but don't include in output (-S)
    # Redirect stderr to /dev/null to suppress error messages
    curl -m 5 -sS -d "$message" polliserve:8089/ibridaDB 2>/dev/null || true
}