import json, hashlib, struct, base64, shutil, os
from js import document, console, Uint8Array, window
from pyodide.ffi import create_proxy

class Config:
    TICKS = 20
    CHUNK_SIZE = 100
    PRECISION = 1000
    OUT_DIR = "animations"
    PART_MAP = {}
    SETTINGS = []
    CAMERAS = {}
    
    @staticmethod
    def get_part_ids():
        parts = sorted({p for role in config.PART_MAP.values() for p in role.keys()})
        return {p: i + 1 for i, p in enumerate(parts)}

config = Config()

DEF_MAP = {
    'player1': {'root': 'root', 'head': 'Head', 'body': 'Body', 'leftArm': 'LeftArm', 'rightArm': 'RightArm', 'leftLeg': 'LeftLeg', 'rightLeg': 'RightLeg'},
    'player2': {'root': 'P2root', 'head': 'P2Head', 'body': 'P2Body', 'leftArm': 'P2LeftArm', 'rightArm': 'P2RightArm', 'leftLeg': 'P2LeftLeg', 'rightLeg': 'P2RightLeg'}
}
DEF_SET = ['overrideVanilla', 'lockMovement', 'useCamera']
DEF_CAM = {'shared': 'sharedCamera', 'player1': 'P1Camera', 'player2': 'P2Camera'}

MODEL_DATA = None
ANIM_CACHE = {}

def log(m):
    c = document.getElementById("console")
    c.innerText = f"> {m}\n" + c.innerText

def reset_config(e=None):
    document.getElementById("cfg_ticks").value = "20"
    document.getElementById("cfg_chunk").value = "100"
    document.getElementById("cfg_prec").value = "1000"
    document.getElementById("cfg_settings").value = json.dumps(DEF_SET)
    document.getElementById("cfg_cameras").value = json.dumps(DEF_CAM, indent=2)

    # Call JS function via window
    window.partMap = window.JSON.parse(json.dumps(DEF_MAP))
    window.renderPartMapTable()

    log("Config reset to defaults.")

def read_config():
    try:
        config.TICKS = int(document.getElementById("cfg_ticks").value)
        config.CHUNK_SIZE = int(document.getElementById("cfg_chunk").value)
        config.PRECISION = int(document.getElementById("cfg_prec").value)
        config.PART_MAP = window.getPartMapFromTable().to_py()
        config.SETTINGS = json.loads(document.getElementById("cfg_settings").value)
        config.CAMERAS = json.loads(document.getElementById("cfg_cameras").value)
        return True
    except Exception as e:
        log(f"Config Error: {e}")
        return False

reset_config()

class Compiler:
    def safe_float(self, val, default=0.0):
        try: return float(val)
        except (ValueError, TypeError): return default

    def get_vec(self, dp, keys='xyz'):
        return [self.safe_float(dp.get(k)) for k in keys]

    def catmull_coeff(self, p0, p1, p2, p3):
        return [
            (-p0 + 3*p1 - 3*p2 + p3) * 0.5,
            (2*p0 - 5*p1 + 4*p2 - p3) * 0.5,
            (-p0 + p2) * 0.5, 
            p1
        ]

    def sq_dist(self, a, b): 
        return sum((x-y)**2 for x, y in zip(a, b))

    def write_varint(self, buf, val):
        val = int(val)
        zigzag = (val << 1) ^ (val >> 31)
        while zigzag >= 0x80:
            buf.append((zigzag & 0x7F) | 0x80)
            zigzag >>= 7
        buf.append(zigzag)

    def bake_channel(self, keyframes, channel_name):
        if not keyframes: return []
        
        kfs = sorted(keyframes, key=lambda k: self.safe_float(k['time']))
        count = len(kfs)
        segs = []

        interp_map = {'linear': 1, 'catmullrom': 2, 'bezier': 3}

        for i, cur in enumerate(kfs):
            is_last = (i == count - 1)
            nxt = cur if is_last else kfs[i+1]
            
            t_cur = self.safe_float(cur['time']) * config.TICKS
            t_nxt = self.safe_float(nxt['time']) * config.TICKS
            
            dp_cur, dp_nxt = cur['data_points'][0], nxt['data_points'][0]
            p1, p2 = self.get_vec(dp_cur), self.get_vec(dp_nxt)

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
                    c = self.catmull_coeff(self.safe_float(prev.get(ax)), p1[j], p2[j], self.safe_float(pp.get(ax)))
                    seg['coeffs'].extend(c)

            elif mode == 3: # Bezier
                seg['bezier'] = []
                for ax in 'xyz':
                    seg['bezier'].append({
                        'rt': self.safe_float(dp_cur.get(f'{ax}_right_time')),
                        'rv': self.safe_float(dp_cur.get(f'{ax}_right_value')),
                        'lt': self.safe_float(dp_nxt.get(f'{ax}_left_time')),
                        'lv': self.safe_float(dp_nxt.get(f'{ax}_left_value'))
                    })

            segs.append(seg)
        return segs

    def simplify_segments(self, segs, threshold=0.002**2):
        if len(segs) < 3: return segs

        cleaned = [segs[0]]
        for s in segs[1:]:
            if self.sq_dist(s['value'], cleaned[-1]['value']) > 1e-5:
                cleaned.append(s)
        if cleaned[-1] is not segs[-1]: cleaned.append(segs[-1])

        def rdp(pts):
            if len(pts) < 3: return pts
            start, end = pts[0]['value'], pts[-1]['value']
            denom = self.sq_dist(start, end)
            
            max_d, idx = 0, 0
            for i in range(1, len(pts)-1):
                if pts[i]['interp'] != 1: return pts # Don't simplify curves
                
                curr = pts[i]['value']
                if denom == 0:
                    d = self.sq_dist(curr, start)
                else:
                    t = max(0, min(1, sum((c-s)*(e-s) for c,s,e in zip(curr, start, end)) / denom))
                    proj = [s + t*(e-s) for s,e in zip(start, end)]
                    d = self.sq_dist(curr, proj)
                
                if d > max_d: max_d, idx = d, i
                
            if max_d > threshold:
                return rdp(pts[:idx+1])[:-1] + rdp(pts[idx:])
            return [pts[0], pts[-1]]

        simplified = rdp(cleaned)

        for i in range(len(simplified)):
            s = simplified[i]
            if i < len(simplified) - 1:
                nxt = simplified[i+1]
                s['duration'] = nxt['time'] - s['time']
                s['delta'] = [nxt['value'][k] - s['value'][k] for k in range(3)]
            else:
                s['duration'] = 0; s['delta'] = [0,0,0]
                
        return simplified

    def serialize_stream(self, segments, duration):
        segments.sort(key=lambda x: (x['tick'], x['pid'], x['cid']))
        chunks = []
        buf = bytearray(struct.pack('>hh', duration, len(segments)))
        
        ctx = {'pid': -1, 'cid': -1, 'time': 0, 'val': [0, 0, 0]}

        for item in segments:
            s = item['data']
            to_int = lambda v: [int(round(x * config.PRECISION)) for x in v]
            
            val_i = to_int(s['value'])
            delta_i = to_int(s['delta'])
            
            new_ctx = (item['pid'] != ctx['pid'] or item['cid'] != ctx['cid'])
            inherit = not new_ctx and all(abs(val_i[k] - ctx['val'][k]) < 1e-3 for k in range(3))
            zero_delta = sum(abs(x) for x in delta_i) < 1e-3
            ip_bit = {2: 1, 3: 2}.get(s['interp'], 0)
            
            flag = (new_ctx) | (inherit << 1) | (zero_delta << 2) | (ip_bit << 3)
            item_buf = bytearray([flag])
            
            if new_ctx:
                item_buf.append(((item['pid'] & 0x1F) << 3) | (item['cid'] & 0x07))
                ctx.update({'pid': item['pid'], 'cid': item['cid'], 'time': 0})
                
            self.write_varint(item_buf, s['time'] - ctx['time'])
            ctx['time'] = s['time']
            self.write_varint(item_buf, s['duration'])
            
            if not inherit: 
                for v in val_i: self.write_varint(item_buf, v)
            if not zero_delta: 
                for d in delta_i: self.write_varint(item_buf, d)
            
            ctx['val'] = [v + d for v, d in zip(val_i, delta_i)]

            if s['interp'] == 2:
                for c in s.get('coeffs', []): self.write_varint(item_buf, c * 100)
            elif s['interp'] == 3:
                dur = s['duration'] or 1.0
                for b in s.get('bezier', []):
                    for t_handle in (b['lt'], b['rt']):
                        norm = abs(t_handle * config.TICKS) / dur
                        item_buf.append(int(max(0, min(255, norm * 255))))
                    self.write_varint(item_buf, b['lv'] * 10000)
                    self.write_varint(item_buf, b['rv'] * 10000)

            if len(buf) + len(item_buf) > config.CHUNK_SIZE:
                chunks.append(base64.b64encode(buf).decode('ascii'))
                buf = bytearray()
                ctx = {'pid': -1, 'cid': -1, 'time': 0, 'val': [0,0,0]}
            buf.extend(item_buf)

        if buf: chunks.append(base64.b64encode(buf).decode('ascii'))
        return chunks

compiler = Compiler()

def get_structure(model):
    els = {e['uuid']:e for e in model.get('elements',[])}
    def parse(n):
        if isinstance(n, str):
            e = els.get(n)
            return {'type':'cube', 'from':e['from'], 'to':e['to'], 'rotation':e.get('rotation'), 'origin':e.get('origin')} if e else None
        node = {'type':'bone', 'name':n['name'], 'origin':n.get('origin',[0,0,0]), 'rotation':n.get('rotation',[0,0,0]), 'children':[]}
        for c in n.get('children', []):
            r = parse(c)
            if r: node['children'].append(r)
        return node
    return json.dumps({'roots': [parse(x) for x in model.get('outliner',[]) if parse(x)]})

async def load_model(e):
    global MODEL_DATA, ANIM_CACHE
    if not read_config(): return
    inp = document.getElementById("fileInput")
    if not inp.files.length: return log("No file.")
    log("Loading...")
    
    txt = await inp.files.item(0).text()
    MODEL_DATA = json.loads(txt)
    
    if hasattr(window, 'buildModel'):
        window.buildModel(get_structure(MODEL_DATA))
    
    lst = document.getElementById("anim-list-container")
    lst.innerHTML = ""
    ANIM_CACHE = {}
    
    anims = MODEL_DATA.get('animations', [])
    log(f"Found {len(anims)} animations.")
    
    for anim in anims:
        name = anim['name']
        parts = {}
        max_t = 0
        for k,v in anim.get('animators',{}).items():
            if v.get('type')!='effect':
                parts[v['name']] = v['keyframes']
                for kf in v['keyframes']: max_t = max(max_t, compiler.safe_float(kf['time']))
        
        dur = int(max_t * config.TICKS)
        ANIM_CACHE[name] = {'raw': parts, 'duration': dur, 'obj': anim}
        
        div = document.createElement("div")
        div.className = "anim-row"
        cb = document.createElement("input")
        cb.type = "checkbox"; cb.checked = True; cb.id = f"cb_{name}"
        lbl = document.createElement("div")
        lbl.className = "anim-name"; lbl.innerText = name
        
        def click(evt, n=name):
            if not read_config(): return
            window.playAnim(json.dumps({'name':n, 'duration':ANIM_CACHE[n]['duration'], 'raw_parts':ANIM_CACHE[n]['raw']}), config.TICKS)
            for x in document.getElementsByClassName("anim-row"): x.classList.remove("active")
            evt.currentTarget.classList.add("active")
            
        div.onclick = create_proxy(click)
        def stop(evt): evt.stopPropagation()
        cb.onclick = create_proxy(stop)
        
        div.appendChild(cb); div.appendChild(lbl); lst.appendChild(div)
        
    document.getElementById("btnBake").disabled = False

async def bake_selected(e):
    if not MODEL_DATA or not read_config(): return
    sel = [n for n in ANIM_CACHE if document.getElementById(f"cb_{n}").checked]
    if not sel: return log("Select animations.")
    log(f"Baking {len(sel)} animations...")
    
    if os.path.exists("animations"): shutil.rmtree("animations")
    os.makedirs("animations", exist_ok=True)
    
    part_ids = config.get_part_ids()
    manifest = {'anims': {}, 'neededParts': {}, 'ids': part_ids}
    part_usage = {k: set() for k in part_ids}

    for name in sel:
        anim = ANIM_CACHE[name]['obj']
        raw = json.dumps(anim, sort_keys=True, separators=(',', ':'))
        ahash = hashlib.sha256(raw.encode()).hexdigest()
        manifest['anims'][name] = ahash
        
        raw_parts = {}
        max_time = 0
        events = []
        
        for anim_node in anim.get('animators', {}).values():
            if anim_node.get('type') == 'effect':
                for k in anim_node['keyframes']:
                    if k.get('channel') == 'timeline':
                        dp = k.get('data_points', [{}])[0]
                        t_val = compiler.safe_float(k['time'])
                        events.append({'tick': int(t_val*config.TICKS), 'script': dp.get('script', '')})
            else:
                raw_parts[anim_node['name']] = anim_node['keyframes']
                for k in anim_node['keyframes']:
                    max_time = max(max_time, compiler.safe_float(k['time']))
        
        dur = int(max_time * config.TICKS)
        settings_out = {}
        def check_active(bone_name):
            kfs = raw_parts.get(bone_name, [])
            for k in kfs:
                if k.get('channel') == 'scale':
                    dp = k['data_points'][0]
                    val = (compiler.safe_float(dp.get('x',0)) + 
                           compiler.safe_float(dp.get('y',0)) + 
                           compiler.safe_float(dp.get('z',0))) / 3.0
                    if val > 0.1: return True
            return False

        for s_key in config.SETTINGS: settings_out[s_key] = check_active(s_key)
        settings_out['cameras'] = {}
        if settings_out.get('useCamera'):
            for key, bone in config.CAMERAS.items(): settings_out['cameras'][key] = check_active(bone)
        else:
            for key in config.CAMERAS: settings_out['cameras'][key] = False

        streams = {}
        for bb_name, kfs_list in raw_parts.items():
            role, internal = next(((r, i) for r, map in config.PART_MAP.items() for i, bb in map.items() if bb == bb_name), (None, None))
            if not role: continue
            
            part_usage[internal].add(name)
            current_pid = part_ids[internal]
            
            channels = {}
            for k in kfs_list: channels.setdefault(k['channel'], []).append(k)

            for ch_name in ['position', 'rotation', 'scale']:
                if ch_name not in channels: continue
                segs = compiler.bake_channel(channels[ch_name], ch_name)
                segs = compiler.simplify_segments(segs, threshold=0.1**2 if ch_name=='rotation' else 0.002**2)
                if segs and (segs[-1]['time'] + segs[-1]['duration'] < dur): segs[-1]['duration'] = dur - segs[-1]['time']
                if role not in streams: streams[role] = []
                streams[role].append([{'tick': segs[0]['time'], 'pid': current_pid, 'cid': ['position', 'rotation', 'scale'].index(ch_name) + 1, 'data': s} for s in segs])

        final_streams = {r: compiler.serialize_stream([x for sub in s for x in sub], dur) for r, s in streams.items()}
        cams = {}
        if settings_out.get('useCamera'):
            for key, bone in config.CAMERAS.items():
                if not settings_out['cameras'].get(key): continue
                kfs = raw_parts.get(bone, [])
                if not kfs: continue
                cam_role = {}
                by_ch = {}
                for k in kfs: by_ch.setdefault(k['channel'], []).append(k)
                for ch in ['position', 'rotation', 'scale']:
                    if ch not in by_ch: continue
                    mode_name = "camera_scale" if ch == "scale" else ch
                    bk = compiler.bake_channel(by_ch[ch], mode_name) 
                    bk = compiler.simplify_segments(bk)
                    if bk and (bk[-1]['time'] + bk[-1]['duration'] < dur): bk[-1]['duration'] = dur - bk[-1]['time']

                    if ch == 'scale': cam_role['timeline'] = [{'tick': s['time'], 'active': s['value'][0] > 0.5} for s in bk]
                    else:
                        json_segs = []
                        for s in bk:
                            js = {'tick': round(s['time'], 2), 'duration': round(s['duration'], 2), 'value': [round(x,4) for x in s['value']], 'delta': [round(x,4) for x in s['delta']], 'interp': s['interp']}
                            if s['interp'] == 2: js['catmull'] = {ax: s.get(f'c{ax}') for ax in 'xyz' if f'c{ax}' in s}
                            json_segs.append(js)
                        cam_role[ch] = json_segs
                if cam_role: cams[key] = cam_role

        out = {'name': name, 'hash': ahash, 'duration': dur, 'settings': settings_out, 'streams': final_streams, 'cameras': cams, 'events': sorted(events, key=lambda x: x['tick'])}
        with open(os.path.join(config.OUT_DIR, f"{ahash}.json"), 'w') as f: json.dump(out, f)

    manifest['neededParts'] = {k: sorted(list(v)) for k, v in part_usage.items() if v}
    with open(os.path.join(config.OUT_DIR, "manifest.json"), 'w') as f: json.dump(manifest, f, indent=2)

    log("Zipping...")
    shutil.make_archive("results", 'zip', config.OUT_DIR)
    with open("results.zip", "rb") as f: zip_data = f.read()
    
    js_array = Uint8Array.new(len(zip_data))
    js_array.assign(zip_data)
    log(await window.saveZip(js_array))