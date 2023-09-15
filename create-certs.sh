#!/bin/bash
#
# Creates all needed certificates for a Linkerd deployment.

# Default certificate directory
certificate_dir="certs"

# Function to display the help message
show_help() {
    echo "Creates all needed certificates for a Linkerd deployment."
    echo
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help              Display this help message"
    echo "  -d, --certificate-dir   Certificate directory of the root CA certificates. (default: $certificate_dir)"
    echo "                          We assume that there is a 'trustanchor' and 'webhook' directory below the 'certificate-dir'"
    echo "                          and that both of them contain sops encrypted files 'root.asc.crt' and 'root.asc.key'."
    exit 1
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--certificate-dir)
            shift
            certificate_dir="$1"
            ;;
        -h|--help)
            show_help
            ;;
        *)
            show_help
            ;;
    esac
    shift
done

echo "CAUTION: This script will override any of your old secrets!"
read -p "Do you want to continue (y/n)? " answer

if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Exiting..."
    exit 0
fi

rm -rf "$certificate_dir"
mkdir -p "$certificate_dir/trustanchor"
mkdir -p "$certificate_dir/webhooks"

step-cli certificate create root.linkerd.cluster.local "$certificate_dir/trustanchor/root.asc.crt" "$certificate_dir/trustanchor/root.asc.key" \
  --profile root-ca --no-password --insecure

step-cli certificate create webhook.linkerd.cluster.local "$certificate_dir/webhooks/root.asc.crt" "$certificate_dir/webhooks/root.asc.key" \
  --profile root-ca --no-password --insecure --san webhook.linkerd.cluster.local

sops -e -i "$certificate_dir/trustanchor/root.asc.crt"
sops -e -i "$certificate_dir/trustanchor/root.asc.key"
sops -e -i "$certificate_dir/webhooks/root.asc.crt"
sops -e -i "$certificate_dir/webhooks/root.asc.key"
