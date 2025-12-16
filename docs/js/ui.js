window.partMap = {}; 

let roles = [];
let internalParts = [];

window.switchTab = function(name) {
    document.querySelectorAll('.panel').forEach(p => p.style.display = 'none');
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.getElementById('panel-' + name).style.display = 'flex';
    event.target.classList.add('active');
}

function rebuildIndexes() {
    roles = Object.keys(window.partMap);
    internalParts = [...new Set(
        roles.flatMap(r => Object.keys(window.partMap[r] || {}))
    )];
}

window.renderPartMapTable = function() {
    const head = document.getElementById("partmap-head");
    const body = document.getElementById("partmap-body");

    rebuildIndexes();
    head.innerHTML = "";
    body.innerHTML = "";

    const hr = document.createElement("tr");
    let html = `<th style="width:120px; color:#fff;">Part ID</th>`;
    roles.forEach(r => {
        html += `<th>
            <div class="flex-between">
                <span>${r}</span>
                <button class="btn-remove" onclick="removeRole('${r}')" title="Remove Role">&times;</button>
            </div>
        </th>`;
    });
    html += `<th style="width:36px"></th>`;
    hr.innerHTML = html;
    head.appendChild(hr);

    internalParts.forEach(part => {
        const tr = document.createElement("tr");
        tr.innerHTML = `<td><input value="${part}" disabled></td>`;

        roles.forEach(role => {
            const val = window.partMap?.[role]?.[part] ?? "";
            const td = document.createElement("td");
            const inp = document.createElement("input");
            inp.value = val;
            inp.placeholder = "Bone Name";
            inp.oninput = () => {
                window.partMap[role] ??= {};
                window.partMap[role][part] = inp.value;
            };
            td.appendChild(inp);
            tr.appendChild(td);
        });

        const rm = document.createElement("td");
        rm.style.textAlign = "center";
        rm.innerHTML = `<button class="btn-remove" title="Remove Part Row">&times;</button>`;
        rm.firstChild.onclick = () => removePart(part);
        tr.appendChild(rm);

        body.appendChild(tr);
    });
}

window.addInternalPart = function() {
    const name = prompt("Internal part name (ID used in script)");
    if (!name) return;
    roles.forEach(r => {
        window.partMap[r] ??= {};
        window.partMap[r][name] = "";
    });
    window.renderPartMapTable();
}

window.addRole = function() {
    const name = prompt("Role name (e.g. player3)");
    if (!name || window.partMap[name]) return;
    window.partMap[name] = {};
    internalParts.forEach(p => window.partMap[name][p] = "");
    window.renderPartMapTable();
}

window.removePart = function(part) {
    if(!confirm(`Remove part ID '${part}'?`)) return;
    roles.forEach(r => delete window.partMap[r]?.[part]);
    window.renderPartMapTable();
}

window.removeRole = function(role) {
    if(!confirm(`Remove role '${role}'?`)) return;
    delete window.partMap[role];
    window.renderPartMapTable();
}

window.getPartMapFromTable = function() {
    return structuredClone(window.partMap);
}