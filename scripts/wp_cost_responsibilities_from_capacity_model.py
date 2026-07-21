"""Map the 118 legacy capacity-model tasks onto the 164 role-card responsibilities.

The legacy rows carry the user's OWN effort numbers (798.6 h/mo). The promoted
responsibilities carry the org structure but no numbers. Transferring the former
onto the latter gives real load using real figures, instead of invented ones.

Each entry: legacy task name -> (card key, distinctive substring of the target
responsibility). Several legacy rows may target one responsibility; their hours
are summed.
"""
import json, collections, sys, os

S = os.path.dirname(os.path.abspath(__file__)) + '/'

CARD = {
    'CS':     'Customer Service & Operations Assistant',
    'HR':     'HR Manager',
    'KIOSK':  'Kiosk Sales Representative',
    'OPS':    'Operations Manager',
    'RETAIL': 'Retail & E-commerce Operations Manager',
    'SOA':    'Sales & Ops Assistant',
    'TECH':   'Technical Product & Purchasing Specialist',
}

MAP = {
    # ---- Technical Product & Purchasing (Marvin) ----
    'SD card flashing — OS + games':            ('TECH', 'Lead the flashing, installation'),
    'Build master image for a NEW model':       ('TECH', 'Compile and maintain approved games'),
    'Curate game set per model':                ('TECH', 'Compile and maintain approved games'),
    'Firmware / OS version updates':            ('TECH', 'Compile and maintain approved games'),
    'Device functional testing':                ('TECH', 'Ensure completed devices meet setup'),
    'Maintain master image library':            ('TECH', 'Maintain standard setup files'),
    'Device repair service':                    ('TECH', 'Diagnose common hardware'),
    'Walk-in repair / service intake':          ('TECH', 'Test incoming samples'),
    'Warranty claim against supplier':          ('TECH', 'Record findings, recurring defects'),
    'Supplier claims (damaged / short-shipped)':('TECH', 'Record findings, recurring defects'),
    'Supplier discovery & canvassing':          ('TECH', 'Source and compare products'),
    'Supplier vetting / qualification':         ('TECH', 'Source and compare products'),
    'Quote comparison & supplier selection':    ('TECH', 'Request quotations, verify specifications'),
    'Quotations & volume pricing':              ('TECH', 'Request quotations, verify specifications'),
    'Price negotiation':                        ('TECH', 'Request quotations, verify specifications'),
    'PO placement / order confirmation':        ('TECH', 'Coordinate with management and operations regarding purchase'),
    'Supplier relationship maintenance':        ('TECH', 'Coordinate with management and operations regarding purchase'),
    'Customs / duties / broker liaison':        ('TECH', 'Coordinate with management and operations regarding purchase'),
    'Freight forwarder coordination':           ('TECH', 'Coordinate with management and operations regarding purchase'),
    'Shipment tracking & ETA chasing':          ('TECH', 'Coordinate with management and operations regarding purchase'),
    'Scan market / spot products worth importing': ('TECH', 'Research new consoles'),
    'Vet new product / brand opportunities':    ('TECH', 'Evaluate specifications, pricing'),
    'Kill / continue review of test brands':    ('TECH', 'Recommend product improvements'),

    # ---- Sales & Ops Assistant (Evander) ----
    'Pick / pack / label orders':               ('SOA', 'Pack, label, check, and dispatch'),
    'Video record packing + upload':            ('SOA', 'Pack, label, check, and dispatch'),
    'Dispatch batching & courier handoff':      ('SOA', 'Pack, label, check, and dispatch'),
    'Repack / insert / retail prep':            ('SOA', 'Assist with receiving, sorting, storage'),
    'Packing station setup / cleanup / supplies':('SOA', 'Assist with receiving, sorting, storage'),
    'Packing material prep (bubble wrap, pouches)': ('SOA', 'Assist with receiving, sorting, storage'),
    'Receiving store delivery & put-away':      ('SOA', 'Assist the Inventory Manager with counting'),
    'Store restock trip from warehouse':        ('SOA', 'Prepare and release kiosk replenishment'),
    'Live selling sessions':                    ('SOA', 'Sell through approved online channels'),

    # ---- Operations Manager (Jeremy) ----
    'Goods-in QC against PO':                   ('OPS', 'Enforce receiving, put-away, transfer'),
    'Put-away / labeling to storage':           ('OPS', 'Enforce receiving, put-away, transfer'),
    'Weekly cycle count':                       ('OPS', 'Schedule stock counts and approve corrections'),
    'Cycle counts (top SKUs)':                  ('OPS', 'Schedule stock counts and approve corrections'),
    'Full physical inventory count':            ('OPS', 'Schedule stock counts and approve corrections'),
    'Daily count — high-value items':           ('OPS', 'Own inventory accuracy across warehouse'),
    'Reorder point / stock cover review':       ('OPS', 'Maintain reorder points, safety stock'),
    'Demand forecast per SKU':                  ('OPS', 'Review sales velocity, current stock'),
    'Decide what to buy and how much':          ('OPS', 'Prepare regular purchasing and restocking'),
    'Slow-mover / ageing stock review':         ('OPS', 'Identify slow-moving, overstocked'),
    'Liquidation execution (Blindbox / Havit)': ('OPS', 'Identify slow-moving, overstocked'),
    'Stock allocation across channels':         ('OPS', 'Coordinate inventory availability across selling'),
    'Returns intake & logging':                 ('OPS', 'Own return, exchange, damage'),
    'Refund / replacement processing':          ('OPS', 'Approve exceptions within authority'),
    'Failed delivery / RTS handling':           ('OPS', 'Monitor packing errors, cancellations'),
    'Bulk order processing & dispatch':         ('OPS', 'Ensure orders are processed accurately'),
    'Scheduling & shift planning':              ('OPS', 'Monitor workload, deadlines, quality'),

    # ---- Customer Service & Operations Assistant ----
    'Pre-sales inquiries & order status':       ('CS', 'Respond to customer inquiries across marketplaces'),
    'Post-purchase follow-up':                  ('CS', 'Handle order status, product questions'),
    'Customer status updates on returns':       ('CS', 'Handle order status, product questions'),
    'Abandoned cart / lead follow-up':          ('CS', 'Follow up on qualified inquiries'),
    'Repeat-buy / winback campaign':            ('CS', 'Follow up on qualified inquiries'),
    'Community / group engagement':             ('CS', 'Assist customers who inquire through Facebook'),
    'Loyalty / community management':           ('CS', 'Assist customers who inquire through Facebook'),
    'Review / rating solicitation':             ('CS', 'Share recurring customer questions'),
    'Pubmat / content creation':                ('CS', 'Create simple product videos'),
    'Product photography / asset creation':     ('CS', 'Produce content for launches'),
    'Social posting & scheduling':              ('CS', 'Assist with basic editing, posting preparation'),
    'Email / SMS blast':                        ('CS', 'Coordinate with the marketing lead'),

    # ---- Kiosk Sales Representative (2 holders) ----
    'In-store demo / customer education':       ('KIOSK', 'Welcome customers, understand their needs'),
    'Service upsell (add-games, repair)':       ('KIOSK', 'Explain product differences, promotions'),
    'Foot traffic / conversion logging':        ('KIOSK', 'Record customer inquiries, reservations'),
    'Store opening routine (setup, float, systems)': ('KIOSK', 'Complete opening and closing procedures'),
    'Store closing routine (Z-read, lockup)':   ('KIOSK', 'Complete opening and closing procedures'),
    'Cash drawer count — opening float':        ('KIOSK', 'Complete opening and closing procedures'),
    'Cash drawer count — closing / Z-reading':  ('KIOSK', 'Complete opening and closing procedures'),
    'POS transaction processing':               ('KIOSK', 'Process payments and receipts accurately'),
    'Daily sales / cash reconciliation':        ('KIOSK', 'Process payments and receipts accurately'),
    'Store BIR receipt / invoice compliance':   ('KIOSK', 'Process payments and receipts accurately'),
    'Invoice / receipt issuance compliance':    ('KIOSK', 'Process payments and receipts accurately'),
    'Petty cash / change fund management':      ('KIOSK', 'Process payments and receipts accurately'),
    'Store cleanliness & housekeeping':         ('KIOSK', 'Keep the kiosk secure, organized'),
    'Security / CCTV review':                   ('KIOSK', 'Keep the kiosk secure, organized'),
    'Visual merchandising / display refresh':   ('KIOSK', 'Maintain a clean, complete, correctly priced'),
    'Price tag / label updates':                ('KIOSK', 'Maintain a clean, complete, correctly priced'),
    'Store sales reporting to HQ':              ('KIOSK', 'Record sales, transfers, replenishment'),
    'Monthly full store inventory count':       ('KIOSK', 'Perform assigned stock counts'),

    # ---- Retail & E-commerce Operations Manager (Marjory) ----
    'New SKU listing creation (all platforms)': ('RETAIL', 'Coordinate listing creation and updates'),
    'Copywriting / SEO per listing':            ('RETAIL', 'Maintain listing standards'),
    'Pricing review vs competitors':            ('RETAIL', 'Maintain listing standards'),
    'Wholesale price list maintenance':         ('RETAIL', 'Maintain listing standards'),
    'Listing refresh / maintenance':            ('RETAIL', 'Ensure approved changes are completed'),
    'Shopify site / theme maintenance':         ('RETAIL', 'Audit listings for errors'),
    'Account management':                       ('RETAIL', 'Maintain a master tracker of products'),
    'Promo / campaign setup per platform':      ('RETAIL', 'Consolidate timelines for launches'),
    'Paid ads setup & monitoring':              ('RETAIL', 'Consolidate timelines for launches'),
    'Consolidate sales data across all channels': ('RETAIL', 'Create and maintain operational trackers'),
    'Mall / landlord coordination & reports':   ('RETAIL', 'Coordinate operational requirements with store staff'),
    'Business permit renewals':                 ('RETAIL', 'Monitor renewal dates, document requirements'),
    'Store equipment maintenance':              ('RETAIL', 'Monitor store and kiosk readiness'),
    'Store supplies & consumables reorder':     ('RETAIL', 'Consolidate operational purchase requests'),
    'Quotation for custom / bulk requests':     ('RETAIL', 'Consolidate operational purchase requests'),
    'Store staff shift scheduling':             ('RETAIL', 'Assign work based on employee roles'),

    # ---- HR Manager (Brixter) ----
    'Payroll run':                              ('HR', 'Manage employee files, contracts'),
    'Payroll data prep & DTR review':           ('HR', 'Manage employee files, contracts'),
    'BIR 1601-C filing':                        ('HR', 'Monitor compliance deadlines'),
    'SSS / PhilHealth / Pag-IBIG remittance':   ('HR', 'Monitor compliance deadlines'),
    'DOLE records upkeep (payroll, DTR, 201)':  ('HR', 'Maintain updated policies, templates'),
    'HR documentation / 201 file upkeep':       ('HR', 'Maintain updated policies, templates'),
    'Recruitment & onboarding':                 ('HR', 'Coordinate hiring from manpower request'),
    'Training & upskilling':                    ('HR', 'Manage role-based onboarding'),
    'Performance reviews':                      ('HR', 'Manage monthly check-ins'),
    'Employee relations / discipline':          ('HR', 'Receive and address employee concerns'),
}

# Deliberately UNMAPPED: finance / COO work with no role card among the 7.
# Leaving these unattributed is honest — inventing a home for them would
# load somebody with work they do not do.
FINANCE = {
    'Bookkeeping / transaction recording', 'Bank reconciliation',
    'Cash deposit / bank run', 'Books of account upkeep',
    'Monthly management reporting / P&L', 'Platform payout reconciliation',
    'Accounts payable / supplier payment runs', 'Supplier payment / remittance',
    'Receivables chasing (credit terms)', 'Petty cash management',
    'Cash-flow forecast', 'VAT / quarterly BIR filings',
    'Annual ITR / financial statements',
}


def main():
    allt = json.load(open(S + 'all.json'))
    cards = {c['id']: c['job_title'] for c in json.load(open(S + 'c.json'))}
    tc = {x['task_id']: x for x in json.load(open(S + 'tc.json'))}
    title_to_id = {v: k for k, v in cards.items()}

    legacy = [t for t in allt if t['role_scorecard_id'] is None]
    promoted = [t for t in allt if t['role_scorecard_id']]

    # target key -> list of contributing legacy tasks
    targets = collections.defaultdict(list)
    unmapped = []
    for t in legacy:
        m = MAP.get(t['name'])
        if not m:
            unmapped.append(t)
            continue
        cardkey, needle = m
        cid = title_to_id[CARD[cardkey]]
        match = [p for p in promoted
                 if p['role_scorecard_id'] == cid and needle.lower() in p['name'].lower()]
        if len(match) != 1:
            print(f'!! {len(match)} matches for {cardkey} / "{needle}" (from "{t["name"]}")',
                  file=sys.stderr)
            unmapped.append(t)
            continue
        targets[match[0]['id']].append(t)

    out = []
    for pid, srcs in targets.items():
        hours = sum(float(tc.get(s['id'], {}).get('hours_per_month_base') or 0) for s in srcs)
        if hours <= 0:
            continue
        # Prefer a volume driver whenever ANY contributing source has one: a
        # driver-linked row responds to the growth multiplier, a manual one is
        # flat forever, and scenario planning only moves on the former.
        drv = next((s for s in srcs if s['times_source'] == 'driver'
                    and float(tc.get(s['id'], {}).get('times_per_month_base') or 0) > 0), None)
        if drv:
            # Keep the driver and factor, then solve minutes-each so the TOTAL
            # still equals the summed effort of every source folded in here.
            times = float(tc[drv['id']]['times_per_month_base'])
            out.append({
                'id': pid, 'times_source': 'driver', 'driver_id': drv['driver_id'],
                'driver_factor': drv['driver_factor'], 'times_manual': None,
                'minutes_source': 'manual',
                'minutes_manual': round(hours * 60.0 / times, 4),
                'rate_id': None, 'node_id': drv['node_id'],
                'cadence': drv['cadence'], 'hours': hours,
                'srcs': [x['name'] for x in srcs],
            })
        else:
            # Nothing volume-driven here -> express the summed effort as one
            # occurrence of N minutes. Honest about being a flat aggregate.
            out.append({
                'id': pid, 'times_source': 'manual', 'driver_id': None,
                'driver_factor': 1, 'times_manual': 1,
                'minutes_source': 'manual', 'minutes_manual': round(hours * 60, 2),
                'rate_id': None, 'node_id': srcs[0]['node_id'],
                'cadence': 'Monthly', 'hours': hours, 'srcs': [x['name'] for x in srcs],
            })

    json.dump(out, open(S + 'plan.json', 'w'), indent=1)

    pro_by_id = {p['id']: p for p in promoted}
    per_card = collections.Counter()
    for o in out:
        per_card[cards[pro_by_id[o['id']]['role_scorecard_id']]] += o['hours']

    print(f'legacy tasks       : {len(legacy)}')
    print(f'  mapped           : {len(legacy) - len(unmapped)}')
    print(f'  finance (no card): {len([t for t in unmapped if t["name"] in FINANCE])}')
    print(f'  other unmapped   : {len([t for t in unmapped if t["name"] not in FINANCE])}')
    print(f'responsibilities costed: {len(out)} of {len(promoted)}')
    print(f'  driver-linked (scales with multiplier): {sum(1 for o in out if o["times_source"] == "driver")}')
    print()
    print(f'{"ROLE":44s} {"hrs/mo":>8s}')
    for k, v in sorted(per_card.items(), key=lambda x: -x[1]):
        print(f'{k[:42]:44s} {v:8.1f}')
    print(f'{"TOTAL transferred":44s} {sum(per_card.values()):8.1f}')
    print()
    for t in unmapped:
        if t['name'] not in FINANCE:
            print(f'  UNMAPPED: {t["name"]}  ({float(tc.get(t["id"],{}).get("hours_per_month_base") or 0):.1f}h)')


main()
