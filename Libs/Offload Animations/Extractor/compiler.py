import struct, base64, config

def safe_float(val, default=0.0):
    try: return float(val)
    except (ValueError, TypeError): return default

def get_vec(dp, keys='xyz'):
    return [safe_float(dp.get(k)) for k in keys]

def catmull_coeff(p0, p1, p2, p3):
    return [
        (-p0 + 3*p1 - 3*p2 + p3) * 0.5,
        (2*p0 - 5*p1 + 4*p2 - p3) * 0.5,
        (-p0 + p2) * 0.5, 
        p1
    ]

def sq_dist(a, b): 
    return sum((x-y)**2 for x, y in zip(a, b))

def write_varint(buf, val):
    val = int(val)
    zigzag = (val << 1) ^ (val >> 31)
    while zigzag >= 0x80:
        buf.append((zigzag & 0x7F) | 0x80)
        zigzag >>= 7
    buf.append(zigzag)

def bake_channel(keyframes, channel_name):
    if not keyframes: return []
    
    kfs = sorted(keyframes, key=lambda k: safe_float(k['time']))
    count = len(kfs)
    segs = []

    interp_map = {'linear': 1, 'catmullrom': 2, 'bezier': 3}

    for i, cur in enumerate(kfs):
        is_last = (i == count - 1)
        nxt = cur if is_last else kfs[i+1]
        
        t_cur = safe_float(cur['time']) * config.TICKS
        t_nxt = safe_float(nxt['time']) * config.TICKS
        
        dp_cur, dp_nxt = cur['data_points'][0], nxt['data_points'][0]
        p1, p2 = get_vec(dp_cur), get_vec(dp_nxt)

        if channel_name == 'camera_scale':
            val = 1.0 if (sum(p1) / 3.0) > 0.1 else 0.0
            p1 = [val] * 3

        mode = interp_map.get(cur.get('interpolation'), 1)
        if is_last: mode = 1

        seg = {
            'time': t_cur, 'duration': max(0, t_nxt - t_cur),
            'value': p1, 'delta': [b-a for a, b in zip(p1, p2)],
            'interp': mode
        }

        if mode == 2: # Catmull
            prev = kfs[i-1]['data_points'][0] if i > 0 else dp_cur
            pp = kfs[i+2]['data_points'][0] if i < count - 2 else dp_nxt
            
            seg['coeffs'] = []
            for j, ax in enumerate('xyz'):
                c = catmull_coeff(safe_float(prev.get(ax)), p1[j], p2[j], safe_float(pp.get(ax)))
                seg['coeffs'].extend(c)

        elif mode == 3: # Bezier
            seg['bezier'] = []
            for ax in 'xyz':
                seg['bezier'].append({
                    'rt': safe_float(dp_cur.get(f'{ax}_right_time')),
                    'rv': safe_float(dp_cur.get(f'{ax}_right_value')),
                    'lt': safe_float(dp_nxt.get(f'{ax}_left_time')),
                    'lv': safe_float(dp_nxt.get(f'{ax}_left_value'))
                })

        segs.append(seg)
    return segs

def simplify_segments(segs, threshold=0.002**2):
    if len(segs) < 3: return segs

    # Filter adjacent duplicates
    cleaned = [segs[0]]
    for s in segs[1:]:
        if sq_dist(s['value'], cleaned[-1]['value']) > 1e-5:
            cleaned.append(s)
    if cleaned[-1] is not segs[-1]: cleaned.append(segs[-1])

    # RDP Algorithm
    def rdp(pts):
        if len(pts) < 3: return pts
        start, end = pts[0]['value'], pts[-1]['value']
        denom = sq_dist(start, end)
        
        max_d, idx = 0, 0
        for i in range(1, len(pts)-1):
            if pts[i]['interp'] != 1: return pts # Don't simplify curves
            
            curr = pts[i]['value']
            if denom == 0:
                d = sq_dist(curr, start)
            else:
                t = max(0, min(1, sum((c-s)*(e-s) for c,s,e in zip(curr, start, end)) / denom))
                proj = [s + t*(e-s) for s,e in zip(start, end)]
                d = sq_dist(curr, proj)
            
            if d > max_d: max_d, idx = d, i
            
        if max_d > threshold:
            return rdp(pts[:idx+1])[:-1] + rdp(pts[idx:])
        return [pts[0], pts[-1]]

    simplified = rdp(cleaned)

    # Re-calculate timing/deltas
    for i in range(len(simplified)):
        s = simplified[i]
        if i < len(simplified) - 1:
            nxt = simplified[i+1]
            s['duration'] = nxt['time'] - s['time']
            s['delta'] = [nxt['value'][k] - s['value'][k] for k in range(3)]
        else:
            s['duration'] = 0; s['delta'] = [0,0,0]
            
    return simplified

def serialize_stream(segments, duration):
    segments.sort(key=lambda x: (x['tick'], x['pid'], x['cid']))
    chunks = []
    buf = bytearray(struct.pack('>hh', duration, len(segments)))
    
    ctx = {'pid': -1, 'cid': -1, 'time': 0, 'val': [0, 0, 0]}

    for item in segments:
        s = item['data']
        # Helper to convert float->fixed precision int
        to_int = lambda v: [int(round(x * config.PRECISION)) for x in v]
        
        val_i = to_int(s['value'])
        delta_i = to_int(s['delta'])
        
        new_ctx = (item['pid'] != ctx['pid'] or item['cid'] != ctx['cid'])
        inherit = not new_ctx and all(abs(val_i[k] - ctx['val'][k]) < 1e-3 for k in range(3))
        zero_delta = sum(abs(x) for x in delta_i) < 1e-3
        
        # Interp bits: 0=Linear(1), 1=Catmull(2), 2=Bezier(3)
        ip_bit = {2: 1, 3: 2}.get(s['interp'], 0)
        
        flag = (new_ctx) | (inherit << 1) | (zero_delta << 2) | (ip_bit << 3)
        
        item_buf = bytearray([flag])
        
        if new_ctx:
            item_buf.append(((item['pid'] & 0x1F) << 3) | (item['cid'] & 0x07))
            ctx.update({'pid': item['pid'], 'cid': item['cid'], 'time': 0})
            
        write_varint(item_buf, s['time'] - ctx['time'])
        ctx['time'] = s['time']
        write_varint(item_buf, s['duration'])
        
        if not inherit: 
            for v in val_i: write_varint(item_buf, v)
        if not zero_delta: 
            for d in delta_i: write_varint(item_buf, d)
        
        ctx['val'] = [v + d for v, d in zip(val_i, delta_i)]

        # Interpolation Specific Data
        if s['interp'] == 2:
            for c in s.get('coeffs', []): 
                write_varint(item_buf, c * 100)
        
        elif s['interp'] == 3:
            dur = s['duration'] or 1.0
            for b in s.get('bezier', []):
                # Compress time handles to byte (0-255)
                for t_handle in (b['lt'], b['rt']):
                    norm = abs(t_handle * config.TICKS) / dur
                    item_buf.append(int(max(0, min(255, norm * 255))))
                
                write_varint(item_buf, b['lv'] * 10000)
                write_varint(item_buf, b['rv'] * 10000)

        if len(buf) + len(item_buf) > config.CHUNK_SIZE:
            chunks.append(base64.b64encode(buf).decode('ascii'))
            buf = bytearray()
            ctx = {'pid': -1, 'cid': -1, 'time': 0, 'val': [0,0,0]}
        
        buf.extend(item_buf)

    if buf: 
        chunks.append(base64.b64encode(buf).decode('ascii'))
    return chunks