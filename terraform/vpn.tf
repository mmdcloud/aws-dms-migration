# ------------------------------------------------------------------------
# VPN Configuration
# ------------------------------------------------------------------------
# Create a HA VPN gateway in GCP (create this first)
resource "google_compute_ha_vpn_gateway" "gcp_vpn_gateway" {
  name    = "gcp-vpn-gateway"
  network = module.source_vpc.vpc_id
  region  = var.source_location
}

# Create a cloud router for BGP with explicit route advertisement
resource "google_compute_router" "gcp_router" {
  name    = "gcp-vpn-router"
  network = module.source_vpc.vpc_id
  region  = var.source_location
  bgp {
    advertise_mode = "CUSTOM"
    # Advertise all subnets including the Cloud SQL subnet
    advertised_groups = ["ALL_SUBNETS"]
    asn               = 65000

    advertised_ip_ranges {
      range       = "10.2.0.0/20"
      description = "Cloud SQL service networking range"
    }
  }
}

# Create a VPN gateway in AWS
resource "aws_vpn_gateway" "aws_vpn_gw" {
  vpc_id          = module.destination_vpc.vpc_id
  amazon_side_asn = 65001
  tags = {
    Name = "aws-vpn-gateway"
  }
}

# Attach VPN gateway to VPC
resource "aws_vpn_gateway_attachment" "vpn_attachment" {
  vpn_gateway_id = aws_vpn_gateway.aws_vpn_gw.id
  vpc_id         = module.destination_vpc.vpc_id
}

# Create customer gateways representing the GCP side
resource "aws_customer_gateway" "gcp_cgw_1" {
  bgp_asn    = 65000
  ip_address = google_compute_ha_vpn_gateway.gcp_vpn_gateway.vpn_interfaces[0].ip_address
  type       = "ipsec.1"

  tags = {
    Name = "aws-customer-gw-1"
  }

  depends_on = [google_compute_ha_vpn_gateway.gcp_vpn_gateway]
}

resource "aws_customer_gateway" "gcp_cgw_2" {
  bgp_asn    = 65000
  ip_address = google_compute_ha_vpn_gateway.gcp_vpn_gateway.vpn_interfaces[1].ip_address
  type       = "ipsec.1"

  tags = {
    Name = "aws-customer-gw-2"
  }

  depends_on = [google_compute_ha_vpn_gateway.gcp_vpn_gateway]
}

# Create VPN connections to GCP
resource "aws_vpn_connection" "vpn_connection_1" {
  vpn_gateway_id      = aws_vpn_gateway.aws_vpn_gw.id
  customer_gateway_id = aws_customer_gateway.gcp_cgw_1.id
  type                = "ipsec.1"
  static_routes_only  = false

  tags = {
    Name = "vpn-connection-1"
  }

  depends_on = [aws_vpn_gateway_attachment.vpn_attachment]
}

resource "aws_vpn_connection" "vpn_connection_2" {
  vpn_gateway_id      = aws_vpn_gateway.aws_vpn_gw.id
  customer_gateway_id = aws_customer_gateway.gcp_cgw_2.id
  type                = "ipsec.1"
  static_routes_only  = false

  tags = {
    Name = "vpn-connection-2"
  }

  depends_on = [aws_vpn_gateway_attachment.vpn_attachment]
}

# Create external VPN gateway representing the AWS side
resource "google_compute_external_vpn_gateway" "aws_vpn_gateway_1" {
  name            = "aws-vpn-gateway"
  redundancy_type = "FOUR_IPS_REDUNDANCY"
  description     = "AWS VPN Gateway"

  interface {
    id         = 0
    ip_address = aws_vpn_connection.vpn_connection_1.tunnel1_address
  }
  interface {
    id         = 1
    ip_address = aws_vpn_connection.vpn_connection_1.tunnel2_address
  }
  interface {
    id         = 2
    ip_address = aws_vpn_connection.vpn_connection_2.tunnel1_address
  }
  interface {
    id         = 3
    ip_address = aws_vpn_connection.vpn_connection_2.tunnel2_address
  }
}

# Create VPN tunnels on GCP side
resource "google_compute_vpn_tunnel" "gcp_tunnel1" {
  name                            = "gcp-tunnel1"
  region                          = var.source_location
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_1.id
  peer_external_gateway_interface = 0
  shared_secret                   = aws_vpn_connection.vpn_connection_1.tunnel1_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 0
  ike_version                     = 2
}

resource "google_compute_vpn_tunnel" "gcp_tunnel2" {
  name                            = "gcp-tunnel2"
  region                          = var.source_location
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_1.id
  peer_external_gateway_interface = 1
  shared_secret                   = aws_vpn_connection.vpn_connection_1.tunnel2_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 0
  ike_version                     = 2
}

resource "google_compute_vpn_tunnel" "gcp_tunnel3" {
  name                            = "gcp-tunnel3"
  region                          = var.source_location
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_1.id
  peer_external_gateway_interface = 2
  shared_secret                   = aws_vpn_connection.vpn_connection_2.tunnel1_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 1
  ike_version                     = 2
}

resource "google_compute_vpn_tunnel" "gcp_tunnel4" {
  name                            = "gcp-tunnel4"
  region                          = var.source_location
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_1.id
  peer_external_gateway_interface = 3
  shared_secret                   = aws_vpn_connection.vpn_connection_2.tunnel2_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 1
  ike_version                     = 2
}

# Create router interfaces for BGP
resource "google_compute_router_interface" "gcp_interface1" {
  name   = "gcp-interface1"
  router = google_compute_router.gcp_router.name
  region = var.source_location
  # FIXED: GCP side uses VGW inside address (AWS's side)
  ip_range   = "${aws_vpn_connection.vpn_connection_1.tunnel1_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel1.name
}

resource "google_compute_router_interface" "gcp_interface2" {
  name       = "gcp-interface2"
  router     = google_compute_router.gcp_router.name
  region     = var.source_location
  ip_range   = "${aws_vpn_connection.vpn_connection_1.tunnel2_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel2.name
}

resource "google_compute_router_interface" "gcp_interface3" {
  name       = "gcp-interface3"
  router     = google_compute_router.gcp_router.name
  region     = var.source_location
  ip_range   = "${aws_vpn_connection.vpn_connection_2.tunnel1_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel3.name
}

resource "google_compute_router_interface" "gcp_interface4" {
  name       = "gcp-interface4"
  router     = google_compute_router.gcp_router.name
  region     = var.source_location
  ip_range   = "${aws_vpn_connection.vpn_connection_2.tunnel2_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel4.name
}

# Create BGP sessions
resource "google_compute_router_peer" "gcp_bgp_peer1" {
  name                      = "gcp-bgp-peer1"
  router                    = google_compute_router.gcp_router.name
  region                    = var.source_location
  peer_ip_address           = aws_vpn_connection.vpn_connection_1.tunnel1_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface1.name
}

resource "google_compute_router_peer" "gcp_bgp_peer2" {
  name                      = "gcp-bgp-peer2"
  router                    = google_compute_router.gcp_router.name
  region                    = var.source_location
  peer_ip_address           = aws_vpn_connection.vpn_connection_1.tunnel2_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface2.name
}

resource "google_compute_router_peer" "gcp_bgp_peer3" {
  name                      = "gcp-bgp-peer3"
  router                    = google_compute_router.gcp_router.name
  region                    = var.source_location
  peer_ip_address           = aws_vpn_connection.vpn_connection_2.tunnel1_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface3.name
}

resource "google_compute_router_peer" "gcp_bgp_peer4" {
  name                      = "gcp-bgp-peer4"
  router                    = google_compute_router.gcp_router.name
  region                    = var.source_location
  peer_ip_address           = aws_vpn_connection.vpn_connection_2.tunnel2_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface4.name
}

# Enable route propagation on AWS private route tables
resource "aws_vpn_gateway_route_propagation" "private_routes" {
  count          = length(module.destination_vpc.private_route_table_ids)
  vpn_gateway_id = aws_vpn_gateway.aws_vpn_gw.id
  route_table_id = module.destination_vpc.private_route_table_ids[count.index]

  depends_on = [
    aws_vpn_gateway_attachment.vpn_attachment,
    aws_vpn_connection.vpn_connection_1,
    aws_vpn_connection.vpn_connection_2
  ]
}

# Add explicit static routes as backup (in case BGP takes time)
resource "aws_route" "to_gcp_subnet" {
  count                  = length(module.destination_vpc.private_route_table_ids)
  route_table_id         = module.destination_vpc.private_route_table_ids[count.index]
  destination_cidr_block = "10.1.0.0/16"
  gateway_id             = aws_vpn_gateway.aws_vpn_gw.id

  depends_on = [
    aws_vpn_gateway_attachment.vpn_attachment,
    google_compute_vpn_tunnel.gcp_tunnel1,
    google_compute_vpn_tunnel.gcp_tunnel2,
    google_compute_vpn_tunnel.gcp_tunnel3,
    google_compute_vpn_tunnel.gcp_tunnel4
  ]
}

# Add route for Cloud SQL peered range
resource "aws_route" "to_gcp_cloudsql_peered" {
  count                  = length(module.destination_vpc.private_route_table_ids)
  route_table_id         = module.destination_vpc.private_route_table_ids[count.index]
  destination_cidr_block = "10.2.0.0/20"
  gateway_id             = aws_vpn_gateway.aws_vpn_gw.id

  depends_on = [
    aws_vpn_gateway_attachment.vpn_attachment,
    google_compute_vpn_tunnel.gcp_tunnel1,
    google_compute_vpn_tunnel.gcp_tunnel2,
    google_compute_vpn_tunnel.gcp_tunnel3,
    google_compute_vpn_tunnel.gcp_tunnel4
  ]
}

# Make sure awscli, boto3 and gcloud are installed on your local system 

# Wait for VPN tunnels and BGP to establish (increased from 60s to 300s)
# Wait for all 4 BGP sessions to reach ESTABLISHED before allowing DMS to proceed.
# Replaces a blind time_sleep: polls every 30s for up to 15 minutes, then fails
# loudly with the actual BGP state so the error is diagnosable.
resource "null_resource" "wait_for_vpn_bgp" {
  depends_on = [
    aws_vpn_gateway_route_propagation.private_routes,
    aws_route.to_gcp_subnet,
    aws_route.to_gcp_cloudsql_peered,
    google_compute_router_peer.gcp_bgp_peer1,
    google_compute_router_peer.gcp_bgp_peer2,
    google_compute_router_peer.gcp_bgp_peer3,
    google_compute_router_peer.gcp_bgp_peer4
  ]

  triggers = {
    vpn_connection_1_id = aws_vpn_connection.vpn_connection_1.id
    vpn_connection_2_id = aws_vpn_connection.vpn_connection_2.id
    router_name         = google_compute_router.gcp_router.name
    region              = var.source_location
    # Route table IDs as a CSV so a change re-triggers the check
    private_route_tables = join(",", module.destination_vpc.private_route_table_ids)
    # Cloud SQL peering range — re-trigger if it ever changes
    cloudsql_range = google_compute_global_address.source_sql_private_ip_address.address
  }

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash"]
    command = <<-EOT
      #!/usr/bin/env bash
      set -euo pipefail

      # ── tunables ──────────────────────────────────────────────────────────
      IPSEC_MAX_RETRIES=20     # 20 × 15s = 5 min for IPSec to come up
      IPSEC_SLEEP_SEC=15
      IPSEC_REQUIRED_UP=2      # At least 2/4 endpoints must be UP (HA minimum)

      BGP_MAX_RETRIES=30       # 30 × 30s = 15 min for BGP to converge
      BGP_SLEEP_SEC=30
      BGP_REQUIRED_ESTABLISHED=4

      CONN1="${self.triggers.vpn_connection_1_id}"
      CONN2="${self.triggers.vpn_connection_2_id}"
      ROUTER="${self.triggers.router_name}"
      REGION="${self.triggers.region}"
      CLOUDSQL_RANGE="${self.triggers.cloudsql_range}/20"
      ROUTE_TABLES="${self.triggers.private_route_tables}"

      SEP="════════════════════════════════════════════════════════════════"

      # ── helpers ───────────────────────────────────────────────────────────
      ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

      dump_diagnostics() {
        echo ""
        echo "$SEP"
        echo "  DIAGNOSTIC DUMP — $(ts)"
        echo "$SEP"

        echo ""
        echo "── AWS: VPN tunnel telemetry ────────────────────────────────"
        aws ec2 describe-vpn-connections \
          --vpn-connection-ids "$CONN1" "$CONN2" \
          --query 'VpnConnections[*].{ID:VpnConnectionId,Tunnels:VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status,LastChanged:LastStatusChange,Reason:StatusMessage}}' \
          --output json 2>/dev/null || echo "  (aws CLI query failed)"

        echo ""
        echo "── AWS: BGP routes in private route tables ──────────────────"
        IFS=',' read -ra RT_IDS <<< "$ROUTE_TABLES"
        for rt in "$${RT_IDS[@]}"; do
          echo "  Route table: $rt"
          aws ec2 describe-route-tables \
            --route-table-ids "$rt" \
            --query "RouteTables[0].Routes[?GatewayId!=null].[DestinationCidrBlock,GatewayId,State,Origin]" \
            --output table 2>/dev/null || echo "  (query failed for $rt)"
        done

        echo ""
        echo "── GCP: BGP peer status ─────────────────────────────────────"
        gcloud compute routers get-status "$ROUTER" \
          --region="$REGION" \
          --format="table(
            result.bgpPeerStatus[].name,
            result.bgpPeerStatus[].state,
            result.bgpPeerStatus[].status,
            result.bgpPeerStatus[].uptime,
            result.bgpPeerStatus[].numLearnedRoutes
          )" 2>/dev/null || echo "  (gcloud query failed)"

        echo ""
        echo "── GCP: Advertised routes from router ───────────────────────"
        gcloud compute routers get-status "$ROUTER" \
          --region="$REGION" \
          --format="json" 2>/dev/null \
          | python3 -c "
import sys, json
data = json.load(sys.stdin)
peers = data.get('result', {}).get('bgpPeerStatus', [])
for p in peers:
    routes = p.get('advertisedRoutes', [])
    print(f\"  Peer: {p.get('name')}  advertised={len(routes)} routes\")
    for r in routes:
        print(f\"    {r.get('destRange')}\")
" 2>/dev/null || echo "  (route parse failed)"

        echo "$SEP"
        echo ""
      }

      # ═════════════════════════════════════════════════════════════════════
      # PHASE 1 — AWS IPSec tunnel endpoints
      # Must have at least $IPSEC_REQUIRED_UP endpoints UP before BGP check.
      # BGP runs on top of IPSec; checking BGP while IPSec is DOWN wastes
      # the entire 15-minute window.
      # ═════════════════════════════════════════════════════════════════════
      echo ""
      echo "$SEP"
      echo "  PHASE 1 — AWS IPSec layer  (need $${IPSEC_REQUIRED_UP}/4 UP)"
      echo "  Max wait: $(( IPSEC_MAX_RETRIES * IPSEC_SLEEP_SEC ))s"
      echo "$SEP"

      for i in $(seq 1 $IPSEC_MAX_RETRIES); do
        TUNNEL_JSON=$(aws ec2 describe-vpn-connections \
          --vpn-connection-ids "$CONN1" "$CONN2" \
          --query 'VpnConnections[*].VgwTelemetry[*].{status:Status,ip:OutsideIpAddress,reason:StatusMessage}' \
          --output json 2>/dev/null || echo '[]')

        TUNNELS_UP=$(echo "$TUNNEL_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
# flatten nested lists
flat = [t for conn in data for t in conn]
up   = [t for t in flat if t.get('status') == 'UP']
print(len(up))
" 2>/dev/null || echo "0")

        echo "  [$(ts)] Attempt $i/$${IPSEC_MAX_RETRIES}: $${TUNNELS_UP}/4 tunnel endpoints UP"

        if [ "$${TUNNELS_UP}" -ge "$${IPSEC_REQUIRED_UP}" ]; then
          echo "  ✓ IPSec layer ready ($${TUNNELS_UP}/4 UP). Proceeding to BGP check."
          break
        fi

        if [ "$i" -eq "$${IPSEC_MAX_RETRIES}" ]; then
          echo ""
          echo "ERROR: IPSec did not reach $${IPSEC_REQUIRED_UP} UP endpoints after $(( IPSEC_MAX_RETRIES * IPSEC_SLEEP_SEC ))s."
          echo "Possible causes: pre-shared key mismatch, firewall blocking UDP 500/4500, or IKE version mismatch."
          dump_diagnostics
          exit 1
        fi

        sleep "$${IPSEC_SLEEP_SEC}"
      done

      # ═════════════════════════════════════════════════════════════════════
      # PHASE 2 — GCP BGP session convergence
      # All 4 peers must reach state=ESTABLISHED and status=UP.
      # ESTABLISHED alone is insufficient — status catches IKE/hold-timer issues
      # that leave BGP partially negotiated.
      # ═════════════════════════════════════════════════════════════════════
      echo ""
      echo "$SEP"
      echo "  PHASE 2 — GCP BGP layer  (need $${BGP_REQUIRED_ESTABLISHED}/4 ESTABLISHED)"
      echo "  Max wait: $(( BGP_MAX_RETRIES * BGP_SLEEP_SEC ))s"
      echo "$SEP"

      for i in $(seq 1 $BGP_MAX_RETRIES); do
        STATUS_JSON=$(gcloud compute routers get-status "$ROUTER" \
          --region="$REGION" \
          --format=json 2>/dev/null || echo '{}')

        ESTABLISHED=$(echo "$STATUS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
peers = data.get('result', {}).get('bgpPeerStatus', [])
ok = [p for p in peers if p.get('status') == 'UP' and p.get('state') == 'ESTABLISHED']
# Print count and summary for logging
for p in peers:
    state  = p.get('state', 'UNKNOWN')
    status = p.get('status', 'UNKNOWN')
    uptime = p.get('uptime', '-')
    routes = p.get('numLearnedRoutes', 0)
    print(f\"PEER {p.get('name')}: state={state} status={status} uptime={uptime} learned_routes={routes}\", file=__import__('sys').stderr)
print(len(ok))
" 2>/tmp/bgp_peer_detail || echo "0")

        # Surface per-peer detail to the apply log
        cat /tmp/bgp_peer_detail 2>/dev/null | sed 's/^/  /' || true

        echo "  [$(ts)] Attempt $i/$${BGP_MAX_RETRIES}: $${ESTABLISHED}/$${BGP_REQUIRED_ESTABLISHED} BGP sessions ESTABLISHED"

        if [ "$${ESTABLISHED}" -ge "$${BGP_REQUIRED_ESTABLISHED}" ]; then
          echo "  ✓ BGP fully converged ($${ESTABLISHED}/$${BGP_REQUIRED_ESTABLISHED}). Proceeding to route check."
          break
        fi

        if [ "$i" -eq "$${BGP_MAX_RETRIES}" ]; then
          echo ""
          echo "ERROR: BGP did not fully converge after $(( BGP_MAX_RETRIES * BGP_SLEEP_SEC ))s."
          echo "Possible causes: ASN mismatch (GCP=65000, AWS=65001), BGP timer mismatch, or missing route advertisement."
          dump_diagnostics
          exit 1
        fi

        sleep "$${BGP_SLEEP_SEC}"
      done

      # ═════════════════════════════════════════════════════════════════════
      # PHASE 3 — Route reachability validation
      # BGP ESTABLISHED does not guarantee routes are propagated to AWS route
      # tables. This phase catches the common split-brain case where BGP is up
      # but the Cloud SQL peering range never appears in AWS routing.
      # ═════════════════════════════════════════════════════════════════════
      echo ""
      echo "$SEP"
      echo "  PHASE 3 — Route reachability ($${CLOUDSQL_RANGE} visible in AWS route tables?)"
      echo "$SEP"

      ROUTE_FOUND=false
      IFS=',' read -ra RT_IDS <<< "$ROUTE_TABLES"

      for rt in "$${RT_IDS[@]}"; do
        HIT=$(aws ec2 describe-route-tables \
          --route-table-ids "$rt" \
          --query "RouteTables[0].Routes[?DestinationCidrBlock=='$${CLOUDSQL_RANGE}'].State" \
          --output text 2>/dev/null || echo "")

        if [ -n "$HIT" ]; then
          echo "  ✓ $${CLOUDSQL_RANGE} found in route table $rt (state: $HIT)"
          ROUTE_FOUND=true
        else
          echo "  ✗ $${CLOUDSQL_RANGE} NOT found in route table $rt"
        fi
      done

      if [ "$ROUTE_FOUND" = "false" ]; then
        echo ""
        echo "ERROR: Cloud SQL peering range $${CLOUDSQL_RANGE} not present in any private route table."
        echo "BGP is ESTABLISHED but routes have not propagated. Check:"
        echo "  1. GCP router is advertising the 10.2.0.0/20 range (see advertised_ip_ranges in google_compute_router)"
        echo "  2. aws_vpn_gateway_route_propagation is applied to all private route tables"
        echo "  3. BGP hold-timer has not expired between phases 2 and 3"
        dump_diagnostics
        exit 1
      fi

      echo ""
      echo "── GCP: Verifying advertised prefix count ────────────────────"
      ADVERTISED=$(gcloud compute routers get-status "$ROUTER" \
        --region="$REGION" \
        --format=json 2>/dev/null \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
peers = data.get('result', {}).get('bgpPeerStatus', [])
total = sum(len(p.get('advertisedRoutes', [])) for p in peers)
print(total)
" 2>/dev/null || echo "0")

      if [ "$${ADVERTISED}" -eq 0 ]; then
        echo "  WARNING: GCP router is advertising 0 routes. DMS may connect but Cloud SQL traffic may not route correctly."
        echo "  Check google_compute_router.bgp.advertised_ip_ranges and advertised_groups."
      else
        echo "  ✓ GCP router advertising $${ADVERTISED} route(s) across all peers."
      fi

      # ═════════════════════════════════════════════════════════════════════
      # ALL PHASES PASSED
      # ═════════════════════════════════════════════════════════════════════
      echo ""
      echo "$SEP"
      echo "  ✓ ALL PHASES PASSED — VPN fully ready for DMS at $(ts)"
      echo "  IPSec: UP | BGP: ESTABLISHED ($${BGP_REQUIRED_ESTABLISHED}/$${BGP_REQUIRED_ESTABLISHED}) | Routes: propagated"
      echo "$SEP"
      echo ""
    EOT
  }
}