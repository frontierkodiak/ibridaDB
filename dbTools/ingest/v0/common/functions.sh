# Function to send ntfy notification
send_notification() {
    local message="$1"
    curl -d "$message" polliserve:8089/ibridaDB
}