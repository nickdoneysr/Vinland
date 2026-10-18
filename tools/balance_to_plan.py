"""Write the balance sweep (docs/balance/fullrun_sweep.csv) into the plan's Balance sheet (Backlog F55).

Usage: python3 tools/balance_to_plan.py docs/Vinland_Game_Development_Plan.xlsx docs/balance/fullrun_sweep.csv
Keeps the sheet's notes below the table ("Changes made from this sweep") and rewrites the table above them.
"""
import csv, sys, copy, collections
import openpyxl
from openpyxl.styles import Font, Alignment

NAMES = {'merchant': 'Merchant', 'farm_household': 'Farm household', 'hunter_boat': 'Hunter-boat', 'shipwright_s_kin': "Shipwright's kin", 'ALL': 'All outfits'}
DESC = {'planner': 'Planner: plans by season, hay sized to the herd, careful captain, sails the day the gate opens',
        'average': 'Average: uneven hands, three haymakers, little drying, average captain, sails weeks late, buys nothing extra',
        'careless': 'Careless: summer-only camp, no hay, no rack, reckless captain, sails late'}

def main(xlsx, path, notes):
    rows = list(csv.DictReader(open(path)))
    wb = openpyxl.load_workbook(xlsx)
    if 'Balance' in wb.sheetnames:
        del wb['Balance']
    ref = wb['Risks']
    ws = wb.create_sheet('Balance', index=wb.sheetnames.index('Revisions'))
    ws['A1'] = ref['A1'].value; ws['A1']._style = copy.copy(ref['A1']._style)
    ws['A2'] = 'Balance sweep  ·  F55: knob changes backed by logged runs'; ws['A2']._style = copy.copy(ref['A2']._style)
    seeds = len(rows) // 12 if rows else 0
    ws['A3'] = ('Whole three-summer runs played by three player models (tests/balance.gd), %d seeds per outfit. Every run is in docs/balance/fullrun_sweep.csv. '
                'Re-run: godot --headless --path . res://tests/balance_runner.tscn -- --n=20, then python3 tools/balance_to_plan.py.' % seeds)
    ws['A3'].alignment = Alignment(wrap_text=True); ws.merge_cells('A3:I3'); ws.row_dimensions[3].height = 32
    hr = [r for r in range(1, 10) if ref.cell(r, 1).value == 'ID'][0]
    hdr = ['Player model', 'Outfit', 'Runs', 'Full saga', 'Dear-bought', 'Other endings', 'Average score', 'Average deaths', 'Average timber home']
    for j, h in enumerate(hdr):
        ws.cell(5, j + 1, h)._style = copy.copy(ref.cell(hr, 1)._style)
    body = ref.cell(hr + 1, 2)._style
    row = 6
    for pol in ['planner', 'average', 'careless']:
        for outfit in ['merchant', 'farm_household', 'hunter_boat', 'shipwright_s_kin', 'ALL']:
            rr = [r for r in rows if r['policy'] == pol and (outfit == 'ALL' or r['outfit'] == outfit)]
            n = len(rr) or 1
            full = sum(1 for r in rr if r['title'] == 'The full saga')
            dear = sum(1 for r in rr if r['title'] == 'A dear-bought saga')
            other = collections.Counter((r['title'] or r['end']) for r in rr if r['title'] not in ('The full saga', 'A dear-bought saga'))
            vals = [pol.capitalize(), NAMES[outfit], len(rr), full / n, dear / n, ', '.join('%s %d' % kv for kv in other.items()) or '—',
                    round(sum(int(r['score']) for r in rr) / n), round(sum(int(r['dead']) for r in rr) / n, 1), round(sum(int(r['timber']) for r in rr) / n, 1)]
            for j, v in enumerate(vals):
                c = ws.cell(row, j + 1, v); c._style = copy.copy(body)
                if j in (3, 4): c.number_format = '0%'
                if outfit == 'ALL': c.font = Font(bold=True)
            row += 1
    row += 1
    ws.cell(row, 1, 'Models').font = Font(bold=True); row += 1
    for pol in ['planner', 'average', 'careless']:
        ws.cell(row, 1, DESC[pol]); ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=9); row += 1
    row += 1
    ws.cell(row, 1, 'Changes made from these sweeps').font = Font(bold=True); row += 1
    for t in notes:
        ws.cell(row, 1, t); ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=9)
        ws.cell(row, 1).alignment = Alignment(wrap_text=True); ws.row_dimensions[row].height = 30; row += 1
    for col, w in zip('ABCDEFGHI', [16, 18, 7, 11, 12, 48, 14, 15, 18]):
        ws.column_dimensions[col].width = w
    ws.freeze_panes = 'A6'
    wb.save(xlsx)

NOTES = [
    'Sweep 1 (8 seeds): planner 100%, average 97%, careless 78% reached the full saga: the arc was too easy to close.',
    'Full saga now also needs no more than "Most deaths for the full saga" (Assumptions, 3). The whole arc with more dead is "A dear-bought saga", scored and named, never scolded (P8).',
    'The camp running itself while you are away sizes hay to the herd (the first pass lost whole herds over the second winter).',
    'The score counts cargo by what it fetched ("Score: per mark of cargo sold", 0.65) instead of timber units, so grade, pelts and Hóp vines count.',
    'Hóp (F27): vines per person raised from 0.25 to 0.5 so the push south pays (planner +5 score on average, with fear and hull risk).',
    'Targets held by the regression test: planner 75%+ full saga, average 15-80%, careless 10% or less; scores and deaths ordered planner > average > careless.',
]

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], NOTES)
