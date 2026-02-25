#!/bin/bash
#
# Test Data Generator for Debezium SAGA Example
# Generates realistic bulk data triggering all possible saga flows
#
# Usage: ./generate-test-data.sh [OPTIONS]
#
# Options:
#   -n, --num-orders NUM    Total number of orders to generate (default: 50)
#   -s, --success PCT       Percentage of successful orders (default: 60)
#   -p, --payment-fail PCT  Percentage of payment failures (default: 25)
#   -c, --credit-fail PCT   Percentage of credit rejections (default: 15)
#   -d, --delay MS          Delay between orders in milliseconds (default: 500)
#   -h, --host HOST         Order service host (default: localhost:8080)
#   --dry-run               Show what would be generated without sending
#   --help                  Show this help message
#
# Saga Flows:
#   1. SUCCESS: Credit approved + Payment processed → Order PROCESSING
#   2. PAYMENT_FAILURE: Credit approved + Payment rejected (card ends in 9999) → Order CANCELLED
#   3. CREDIT_REJECTION: Credit rejected (amount > limit) → Order CANCELLED
#

set -e

# Default configuration
NUM_ORDERS=50
SUCCESS_PCT=60
PAYMENT_FAIL_PCT=25
CREDIT_FAIL_PCT=15
DELAY_MS=500
HOST="localhost:8080"
DRY_RUN=false
CUSTOMER_ID=456  # Pre-seeded customer with credit limit 50000

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Realistic product catalog
declare -a PRODUCTS=(
    "1:Wireless Bluetooth Headphones:7999"
    "2:USB-C Charging Cable:1499"
    "3:Laptop Stand:3499"
    "4:Mechanical Keyboard:12999"
    "5:Wireless Mouse:2999"
    "6:Monitor Arm:8999"
    "7:Webcam HD 1080p:5999"
    "8:USB Hub 7-Port:2499"
    "9:Desk Lamp LED:3999"
    "10:Notebook Stand:1999"
    "11:Screen Protector:999"
    "12:Phone Case:1499"
    "13:Portable Charger:2999"
    "14:HDMI Cable 6ft:1299"
    "15:Ethernet Cable Cat6:899"
    "16:Mouse Pad XL:1999"
    "17:Cable Management Kit:1499"
    "18:Laptop Sleeve 15in:2499"
    "19:USB Flash Drive 64GB:1299"
    "20:External SSD 500GB:8999"
)

# Realistic credit card prefixes (for valid cards)
declare -a CARD_PREFIXES=(
    "4532"  # Visa
    "4916"  # Visa
    "5425"  # Mastercard
    "5582"  # Mastercard
    "3782"  # Amex
    "6011"  # Discover
)

# First names for realistic order generation
declare -a FIRST_NAMES=(
    "James" "Mary" "John" "Patricia" "Robert" "Jennifer"
    "Michael" "Linda" "William" "Elizabeth" "David" "Barbara"
    "Richard" "Susan" "Joseph" "Jessica" "Thomas" "Sarah"
    "Charles" "Karen" "Daniel" "Nancy" "Matthew" "Lisa"
    "Anthony" "Betty" "Mark" "Margaret" "Donald" "Sandra"
)

# Statistics tracking
TOTAL_SENT=0
SUCCESS_COUNT=0
PAYMENT_FAIL_COUNT=0
CREDIT_FAIL_COUNT=0
ERRORS=0

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--num-orders)
                NUM_ORDERS="$2"
                shift 2
                ;;
            -s|--success)
                SUCCESS_PCT="$2"
                shift 2
                ;;
            -p|--payment-fail)
                PAYMENT_FAIL_PCT="$2"
                shift 2
                ;;
            -c|--credit-fail)
                CREDIT_FAIL_PCT="$2"
                shift 2
                ;;
            -d|--delay)
                DELAY_MS="$2"
                shift 2
                ;;
            -h|--host)
                HOST="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate percentages sum to 100
    local total=$((SUCCESS_PCT + PAYMENT_FAIL_PCT + CREDIT_FAIL_PCT))
    if [[ $total -ne 100 ]]; then
        echo -e "${RED}Error: Percentages must sum to 100 (got $total)${NC}"
        exit 1
    fi
}

show_help() {
    head -30 "$0" | tail -28 | sed 's/^# //' | sed 's/^#//'
}

# Generate a realistic credit card number
generate_credit_card() {
    local scenario=$1
    local prefix=${CARD_PREFIXES[$((RANDOM % ${#CARD_PREFIXES[@]}))]}
    
    case $scenario in
        "success")
            # Generate valid card (doesn't end in 9999)
            local suffix=$((1000 + RANDOM % 8999))  # 1000-9998, never 9999
            echo "${prefix}-$((1000 + RANDOM % 9000))-$((1000 + RANDOM % 9000))-${suffix}"
            ;;
        "payment_failure")
            # Card ending in 9999 triggers payment failure
            echo "${prefix}-$((1000 + RANDOM % 9000))-$((1000 + RANDOM % 9000))-9999"
            ;;
        "credit_rejection")
            # Any valid card works for credit rejection (amount triggers it)
            local suffix=$((1000 + RANDOM % 8999))
            echo "${prefix}-$((1000 + RANDOM % 9000))-$((1000 + RANDOM % 9000))-${suffix}"
            ;;
    esac
}

# Get a random product
get_random_product() {
    local idx=$((RANDOM % ${#PRODUCTS[@]}))
    echo "${PRODUCTS[$idx]}"
}

# Determine scenario for this order based on percentages
get_scenario() {
    local order_num=$1
    local success_threshold=$SUCCESS_PCT
    local payment_fail_threshold=$((SUCCESS_PCT + PAYMENT_FAIL_PCT))
    
    # Use random number for distribution (more realistic)
    local bucket=$((RANDOM % 100))
    
    if [[ $bucket -lt $success_threshold ]]; then
        echo "success"
    elif [[ $bucket -lt $payment_fail_threshold ]]; then
        echo "payment_failure"
    else
        echo "credit_rejection"
    fi
}

# Generate payment amount based on scenario
generate_amount() {
    local scenario=$1
    local base_price=$2
    
    case $scenario in
        "credit_rejection")
            # Amount exceeds credit limit (50000 cents = $500)
            echo $((55000 + RANDOM % 20000))  # $550-$750
            ;;
        *)
            # Normal amount based on product price and quantity
            local quantity=$((1 + RANDOM % 5))
            echo $((base_price * quantity))
            ;;
    esac
}

# Generate and send an order
send_order() {
    local order_num=$1
    local scenario=$2
    
    # Get random product
    local product_line=$(get_random_product)
    local product_id=$(echo "$product_line" | cut -d: -f1)
    local product_name=$(echo "$product_line" | cut -d: -f2)
    local product_price=$(echo "$product_line" | cut -d: -f3)
    
    # Generate order details
    local quantity=$((1 + RANDOM % 5))
    local amount=$(generate_amount "$scenario" "$product_price")
    local credit_card=$(generate_credit_card "$scenario")
    local customer_name=${FIRST_NAMES[$((RANDOM % ${#FIRST_NAMES[@]}))]}
    
    # Build JSON payload
    local payload=$(cat <<EOF
{
    "customerId": ${CUSTOMER_ID},
    "productId": ${product_id},
    "quantity": ${quantity},
    "totalPrice": ${amount},
    "creditCardNo": "${credit_card}"
}
EOF
)

    # Format amount for display
    local amount_display=$(awk "BEGIN {printf \"%.2f\", $amount / 100}")
    
    # Scenario label
    local scenario_label=""
    case $scenario in
        "success")
            scenario_label="${GREEN}SUCCESS${NC}"
            ;;
        "payment_failure")
            scenario_label="${YELLOW}PAYMENT_FAIL${NC}"
            ;;
        "credit_rejection")
            scenario_label="${RED}CREDIT_REJECT${NC}"
            ;;
    esac
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "[$order_num] $scenario_label - $product_name x$quantity = \$${amount_display}"
        echo "    Card: $credit_card"
        return 0
    fi
    
    # Send the order
    local response
    response=$(curl -s --max-time 10 -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "http://${HOST}/orders" 2>&1)
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]] && echo "$response" | grep -q "orderId"; then
        local order_id=$(echo "$response" | grep -o '"orderId":[0-9]*' | cut -d: -f2)
        echo -e "[$order_num] Order #${order_id} - $scenario_label - $product_name x$quantity = \$${amount_display}"
        
        case $scenario in
            "success") SUCCESS_COUNT=$((SUCCESS_COUNT + 1)) ;;
            "payment_failure") PAYMENT_FAIL_COUNT=$((PAYMENT_FAIL_COUNT + 1)) ;;
            "credit_rejection") CREDIT_FAIL_COUNT=$((CREDIT_FAIL_COUNT + 1)) ;;
        esac
    else
        echo -e "[$order_num] ${RED}ERROR${NC} - Failed to create order: $response"
        ERRORS=$((ERRORS + 1))
    fi
    
    TOTAL_SENT=$((TOTAL_SENT + 1))
}

# Print configuration summary
print_config() {
    echo ""
    echo "========================================"
    echo "  SAGA Test Data Generator"
    echo "========================================"
    echo ""
    echo "Configuration:"
    echo "  Host:           http://${HOST}"
    echo "  Total Orders:   ${NUM_ORDERS}"
    echo "  Delay:          ${DELAY_MS}ms"
    echo "  Customer ID:    ${CUSTOMER_ID}"
    echo ""
    echo "Scenario Distribution:"
    echo -e "  ${GREEN}Success:${NC}          ${SUCCESS_PCT}% (~$((NUM_ORDERS * SUCCESS_PCT / 100)) orders)"
    echo -e "  ${YELLOW}Payment Failure:${NC}  ${PAYMENT_FAIL_PCT}% (~$((NUM_ORDERS * PAYMENT_FAIL_PCT / 100)) orders)"
    echo -e "  ${RED}Credit Rejection:${NC} ${CREDIT_FAIL_PCT}% (~$((NUM_ORDERS * CREDIT_FAIL_PCT / 100)) orders)"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}[DRY RUN MODE - No orders will be sent]${NC}"
        echo ""
    fi
}

# Print final summary
print_summary() {
    echo ""
    echo "========================================"
    echo "  Generation Complete"
    echo "========================================"
    echo ""
    echo "Results:"
    echo "  Total Sent:       ${TOTAL_SENT}"
    echo -e "  ${GREEN}Success:${NC}          ${SUCCESS_COUNT}"
    echo -e "  ${YELLOW}Payment Failure:${NC}  ${PAYMENT_FAIL_COUNT}"
    echo -e "  ${RED}Credit Rejection:${NC} ${CREDIT_FAIL_COUNT}"
    
    if [[ $ERRORS -gt 0 ]]; then
        echo -e "  ${RED}Errors:${NC}           ${ERRORS}"
    fi
    echo ""
    
    # Expected OCEL event types
    echo "Expected OCEL Event Types:"
    echo "  - order-placement-started"
    echo "  - order-placement-started-credit-approval"
    if [[ $SUCCESS_COUNT -gt 0 ]] || [[ $PAYMENT_FAIL_COUNT -gt 0 ]]; then
        echo "  - order-placement-started-payment (for approved credits)"
    fi
    if [[ $SUCCESS_COUNT -gt 0 ]]; then
        echo "  - order-placement-completed"
    fi
    if [[ $PAYMENT_FAIL_COUNT -gt 0 ]] || [[ $CREDIT_FAIL_COUNT -gt 0 ]]; then
        echo "  - order-placement-aborting (for failures)"
        echo "  - order-placement-aborted"
    fi
    echo "  - purchaseorder-created"
    echo "  - purchaseorder-processing (for successful sagas)"
    echo "  - purchaseorder-cancelled (for failed sagas)"
    echo "  - payment-request (for approved credits)"
    echo ""
}

# Check if order service is available
check_service() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo -n "Checking order service at http://${HOST}... "
    
    if curl -s --connect-timeout 5 "http://${HOST}/orders" -X GET > /dev/null 2>&1 || \
       curl -s --connect-timeout 5 "http://${HOST}" -X GET > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        echo ""
        echo "Error: Cannot connect to order service at http://${HOST}"
        echo "Please ensure the SAGA example is running:"
        echo "  cd external/debezium-examples/saga"
        echo "  docker-compose up -d"
        exit 1
    fi
}

# Main execution
main() {
    parse_args "$@"
    print_config
    check_service
    
    echo "Starting order generation..."
    echo ""
    
    local start_time=$(date +%s)
    
    for ((i=1; i<=NUM_ORDERS; i++)); do
        local scenario=$(get_scenario $i)
        send_order $i "$scenario"
        
        # Add delay between orders (except for last one)
        if [[ $i -lt $NUM_ORDERS ]] && [[ "$DRY_RUN" != "true" ]]; then
            # Use awk for floating point division (more portable than bc)
            sleep $(awk "BEGIN {printf \"%.3f\", $DELAY_MS / 1000}")
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_summary
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "Duration: ${duration} seconds"
        echo ""
        echo "Tip: Wait ~10 seconds for all sagas to complete, then check OCEL output:"
        echo "  docker exec saga-connect-1 cat /tmp/ocel-output/saga-events.json | jq '.'"
    fi
}

# Run main
main "$@"
