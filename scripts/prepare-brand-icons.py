"""Convert the checked-in vendor SVG paths to transparent vector PDFs.

Requires reportlab for asset regeneration only; the app loads the checked-in
PDFs through AppKit and has no image or browser runtime dependency.
"""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from reportlab.pdfgen import canvas
from reportlab.lib.colors import toColor

assets = Path(__file__).resolve().parent.parent / 'Sources/MorrowApp/Assets'
for name in ['redis', 'valkey']:
    root = ET.parse(assets / (name + '.svg')).getroot()
    x0, y0, width, height = map(float, root.attrib['viewBox'].split())
    css = ''.join(el.text or '' for el in root.iter() if el.tag.endswith('style'))
    styles = dict(re.findall(r'\.([\w]+)\{([^}]+)\}', css))
    output = canvas.Canvas(str(assets / (name + '.pdf')), pagesize=(width, height), invariant=1)
    output.setTitle(name.title() + ' brand mark')
    output.translate(0, height)
    output.scale(1, -1)
    output.translate(-x0, -y0)
    for element in root.iter():
        if not element.tag.endswith('path'): continue
        style = styles.get(element.attrib.get('class', ''), '')
        color = element.attrib.get('fill') or re.search(r'(?:^|;)fill:([^;]+)', style).group(1)
        output.setFillColor(toColor(color))
        tokens = re.findall(r'[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?', element.attrib['d'])
        path = output.beginPath()
        index, command = 0, None
        x = y = sx = sy = 0
        control = None
        previous = None
        while index < len(tokens):
            if tokens[index].isalpha(): command = tokens[index]; index += 1
            upper = command.upper()
            relative = command.islower()
            if upper == 'Z':
                path.close(); x, y = sx, sy; control = None; previous = 'Z'; command = None
                continue
            counts = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4}
            if upper not in counts: raise ValueError('Unsupported SVG command: ' + command)
            count = counts[upper]
            values = list(map(float, tokens[index:index + count])); index += count
            if upper in ['M', 'L', 'C', 'S'] and relative:
                values = [number + (x if i % 2 == 0 else y) for i, number in enumerate(values)]
            if upper == 'M':
                x, y = values; sx, sy = x, y; path.moveTo(x, y)
                command = 'l' if relative else 'L'
            elif upper == 'L': x, y = values; path.lineTo(x, y)
            elif upper == 'H': x = values[0] + (x if relative else 0); path.lineTo(x, y)
            elif upper == 'V': y = values[0] + (y if relative else 0); path.lineTo(x, y)
            elif upper == 'C':
                path.curveTo(*values); control = tuple(values[2:4]); x, y = values[4:]
            elif upper == 'S':
                first = (2*x - control[0], 2*y - control[1]) if previous in ['C', 'S'] and control else (x, y)
                path.curveTo(*first, *values); control = tuple(values[:2]); x, y = values[2:]
            if upper not in ['C', 'S']: control = None
            previous = upper
        output.drawPath(path, fill=1, stroke=0, fillMode=0 if 'fill-rule:evenodd' in style else 1)
    output.showPage()
    output.save()
    print('Prepared', name + '.pdf')
