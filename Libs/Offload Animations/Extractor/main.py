import os, json, hashlib
import config, compiler

def run():
    print("Baking...")
    os.makedirs(config.OUT_DIR, exist_ok=True)
    
    with open(config.MODEL_PATH, 'r', encoding='utf-8') as f:
        model = json.load(f)

    part_ids = config.get_part_ids()

    manifest = {
        'anims': {}, 
        'neededParts': {},
        'ids': part_ids
    }
    
    part_usage = {k: set() for k in part_ids}

    for anim in model.get('animations', []):
        name = anim['name']
        print(f"-> {name}")
        
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

        for s_key in config.SETTINGS:
            settings_out[s_key] = check_active(s_key)

        settings_out['cameras'] = {}
        if settings_out.get('useCamera'):
            for key, bone in config.CAMERAS.items():
                settings_out['cameras'][key] = check_active(bone)
        else:
            for key in config.CAMERAS:
                settings_out['cameras'][key] = False

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
                
                if segs and (segs[-1]['time'] + segs[-1]['duration'] < dur):
                    segs[-1]['duration'] = dur - segs[-1]['time']

                if role not in streams: streams[role] = []
                
                streams[role].append([{
                    'tick': segs[0]['time'], 
                    'pid': current_pid,
                    'cid': ['position', 'rotation', 'scale'].index(ch_name) + 1,
                    'data': s
                } for s in segs])

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
                    
                    if bk and (bk[-1]['time'] + bk[-1]['duration'] < dur):
                        bk[-1]['duration'] = dur - bk[-1]['time']

                    if ch == 'scale': 
                        cam_role['timeline'] = [{'tick': s['time'], 'active': s['value'][0] > 0.5} for s in bk]
                    else:
                        json_segs = []
                        for s in bk:
                            js = {
                                'tick': round(s['time'], 2), 
                                'duration': round(s['duration'], 2),
                                'value': [round(x,4) for x in s['value']],
                                'delta': [round(x,4) for x in s['delta']],
                                'interp': s['interp']
                            }
                            if s['interp'] == 2:
                                js['catmull'] = {ax: s.get(f'c{ax}') for ax in 'xyz' if f'c{ax}' in s}
                            json_segs.append(js)
                        cam_role[ch] = json_segs
                
                if cam_role: cams[key] = cam_role

        out = {
            'name': name,
            'hash': ahash,
            'duration': dur,
            'settings': settings_out,
            'streams': final_streams,
            'cameras': cams,
            'events': sorted(events, key=lambda x: x['tick'])
        }
        with open(os.path.join(config.OUT_DIR, f"{ahash}.json"), 'w') as f:
            json.dump(out, f)

    manifest['neededParts'] = {k: sorted(list(v)) for k, v in part_usage.items() if v}
    with open(os.path.join(config.OUT_DIR, "manifest.json"), 'w') as f:
        json.dump(manifest, f, indent=2)

if __name__ == "__main__":
    run()