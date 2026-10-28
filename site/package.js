(function () {
  'use strict';
  var host = document.getElementById('detail'), id = new URLSearchParams(location.search).get('id');
  function add(tag, text, cls) { var el = document.createElement(tag); el.textContent = text; if (cls) el.className = cls; host.appendChild(el); return el; }
  fetch('packages.json', {cache: 'no-store'}).then(function (r) { if (!r.ok) throw new Error('Catalog unavailable. Please try again later.'); return r.json(); }).then(function (packages) {
    var pkg = packages.filter(function (entry) { return entry.id === id; })[0]; if (!pkg) throw new Error('This package is not in the current catalog.');
    document.title = pkg.name + ' — Phoni Repo'; host.textContent = ''; add('span', 'PHONI REPO / THE COLLECTION', 'eyebrow'); add('h1', pkg.name);
    var meta = add('div', '', 'detail-meta'); [pkg.version, pkg.section, 'Rootful / ' + pkg.architecture].forEach(function (text) { var badge = document.createElement('span'); badge.className = 'badge'; badge.textContent = text; meta.appendChild(badge); });
    add('p', pkg.description); var actions = add('div', '', 'actions'); var sileo = document.createElement('a'); sileo.className = 'button primary'; sileo.href = 'sileo://package/' + encodeURIComponent(pkg.id); sileo.textContent = 'Open in Sileo ↗'; actions.appendChild(sileo);
    var download = document.createElement('a'); download.className = 'button secondary'; download.href = pkg.filename; download.textContent = 'Download .deb ↓'; actions.appendChild(download);
    add('p', 'Dependencies: ' + (pkg.depends || 'None declared.')); add('p', 'Developer: ' + pkg.author); add('p', 'Compatibility comes from the package metadata. On-device testing is still needed. Add this source to Sileo before opening a package.');
    add('p', 'SHA256: ' + pkg.sha256, 'tiny');
  }).catch(function (e) { host.textContent = ''; add('h1', 'Package unavailable'); add('p', e.message); var back = add('a', '← Browse the collection', 'text-link'); back.href = './#packages'; });
}());
