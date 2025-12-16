import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

let scene, camera, renderer, controls, rootGroup, boneMap = {}, clock = new THREE.Clock();
const el = document.getElementById('viewport');

function init() {
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0f0f0f);
    scene.add(new THREE.GridHelper(30, 30, 0x333333, 0x1a1a1a), new THREE.AxesHelper(2), new THREE.AmbientLight(0xffffff, 0.6));
    
    const dir = new THREE.DirectionalLight(0xffffff, 0.8);
    dir.position.set(5, 10, -5);
    scene.add(dir);

    camera = new THREE.PerspectiveCamera(45, el.clientWidth / el.clientHeight, 0.1, 1000);
    camera.position.set(0, 10, -35);

    renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(el.clientWidth, el.clientHeight);
    el.appendChild(renderer.domElement);

    controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 5, 0);

    window.addEventListener('resize', () => {
        camera.aspect = el.clientWidth / el.clientHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(el.clientWidth, el.clientHeight);
    });
    renderer.setAnimationLoop(() => {
        controls.update();
        window.updateAnimation?.(clock.getDelta());
        renderer.render(scene, camera);
    });
}

window.buildModel = (jsonStr) => {
    if (rootGroup) scene.remove(rootGroup);
    rootGroup = new THREE.Group();
    rootGroup.scale.setScalar(1/16);
    scene.add(rootGroup);
    boneMap = {};

    const rad = (deg) => THREE.MathUtils.degToRad(deg);
    const setT = (obj, [x, y, z], [rx, ry, rz] = [0,0,0]) => {
        obj.position.set(x, y, z);
        obj.rotation.set(rad(rx), rad(ry), rad(rz), 'ZYX');
    };

    const build = (node, parent, [px, py, pz] = [0,0,0]) => {
        const [nx, ny, nz] = node.origin || [0,0,0];
        const group = new THREE.Group();
        group.name = node.name;
        setT(group, [nx - px, ny - py, nz - pz], node.rotation);
        
        group.userData = { basePos: group.position.clone(), baseRot: group.rotation.clone(), baseScl: group.scale.clone() };
        boneMap[node.name] = parent.add(group) && group;

        node.children?.forEach(c => c.type === 'bone' ? build(c, group, [nx, ny, nz]) : buildCube(c, group, [nx, ny, nz]));
    };

    const buildCube = (node, parent, [bx, by, bz]) => {
        const [w, h, d] = [node.to[0]-node.from[0], node.to[1]-node.from[1], node.to[2]-node.from[2]];
        const [cx, cy, cz] = [node.from[0]+w/2, node.from[1]+h/2, node.from[2]+d/2];
        const mesh = new THREE.Mesh(
            new THREE.BoxGeometry(w, h, d), 
            new THREE.MeshLambertMaterial({color: 0x3794ff, transparent: true, opacity: 0.8})
        );
        
        if (node.rotation) {
            const pivot = new THREE.Group();
            const [px, py, pz] = node.origin || [cx, cy, cz];
            setT(pivot, [px - bx, py - by, pz - bz], node.rotation);
            mesh.position.set(cx - px, cy - py, cz - pz);
            parent.add(pivot.add(mesh) && pivot);
        } else {
            mesh.position.set(cx - bx, cy - by, cz - bz);
            parent.add(mesh);
        }
    };
    JSON.parse(jsonStr).roots.forEach(r => build(r, rootGroup));
};

window.playAnim = (jsonStr, ticks) => {
    const { duration, raw_parts } = JSON.parse(jsonStr);
    let time = 0;
    const dur = duration / ticks;
    
    window.updateAnimation = (dt) => {
        time = (time + dt) % dur;
        const tick = time * ticks;

        Object.entries(boneMap).forEach(([name, bone]) => {
            const tracks = raw_parts[name];
            if (!tracks) return;

            bone.position.copy(bone.userData.basePos);
            bone.rotation.copy(bone.userData.baseRot);
            bone.scale.copy(bone.userData.baseScl);

            ['position', 'rotation', 'scale'].forEach(channel => {
                const kfs = tracks.filter(k => k.channel === channel);
                if (!kfs.length) return;
                
                let i = kfs.findIndex((k, idx) => kfs[idx + 1]?.time * ticks > tick);
                if (i === -1) i = kfs.length - 1;
                
                const a = kfs[i], b = kfs[i + 1] || a;
                const alpha = (a === b) ? 0 : (tick - a.time * ticks) / ((b.time - a.time) * ticks);
                
                const val = (axis) => THREE.MathUtils.lerp(+(a.data_points[0][axis] || 0), +(b.data_points[0][axis] || 0), alpha);
                const x = val('x'), y = val('y'), z = val('z');

                if (channel === 'position') { bone.position.x -= x; bone.position.y += y; bone.position.z -= z; }
                if (channel === 'rotation') bone.rotation.set(THREE.MathUtils.degToRad(x), THREE.MathUtils.degToRad(y), THREE.MathUtils.degToRad(z), 'ZYX');
                if (channel === 'scale') bone.scale.set(x, y, z);
            });
        });
    }
};

window.saveZip = async (bytes) => {
    const url = URL.createObjectURL(new Blob([bytes], {type: 'application/zip'}));
    Object.assign(document.createElement('a'), { href: url, download: 'animations.zip' }).click();
    setTimeout(() => URL.revokeObjectURL(url), 100);
    return "Downloaded via browser.";
};

init();