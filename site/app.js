(function () {
  'use strict';
  var source = 'https://realphoni.github.io/phoni-repo/', packages = [], filter = 'all', loaded = false;
  var query = document.getElementById('package-search'), list = document.getElementById('package-list');
  var toastTimer;
  function toast(message) {
    var el = document.getElementById('toast'); el.textContent = message; el.classList.add('visible');
    clearTimeout(toastTimer); toastTimer = setTimeout(function () { el.classList.remove('visible'); }, 3500);
  }
  document.getElementById('copy-source').addEventListener('click', function () {
    function fallback() {
      var field = document.createElement('textarea'); field.value = source; field.style.position = 'fixed'; field.style.top = '0'; field.style.opacity = '0';
      document.body.appendChild(field); field.select(); field.setSelectionRange(0, source.length);
      var copied = false; try { copied = document.execCommand('copy'); } catch (e) { /* manual fallback below */ }
      field.remove(); toast(copied ? 'Source URL copied.' : 'Select and copy the source URL above.');
    }
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(source).then(function () { toast('Source URL copied.'); }, fallback);
    else fallback();
  });
  function element(tag, cls, text) { var el = document.createElement(tag); if (cls) el.className = cls; if (text) el.textContent = text; return el; }
  function message(title, description, linkText, href) {
    list.textContent = ''; var box = element('div', 'empty-state'); box.appendChild(element('span', 'empty-symbol', '＋')); box.appendChild(element('h3', '', title)); box.appendChild(element('p', '', description));
    if (href) { var link = element('a', 'text-link', linkText); link.href = href; box.appendChild(link); } list.appendChild(box);
  }
  function render() {
    if (!loaded) return;
    var term = query.value.trim().toLowerCase();
    var matches = packages.filter(function (pkg) { return (filter === 'all' || pkg.section === filter) && [pkg.name, pkg.description, pkg.id].join(' ').toLowerCase().indexOf(term) !== -1; });
    document.getElementById('package-count').textContent = packages.length + (packages.length === 1 ? ' package' : ' packages');
    if (!packages.length) { message('Nothing here yet.', 'I haven’t uploaded any tweaks yet. Check back later.'); return; }
    if (!matches.length) { message('No matching tweaks.', 'Try another search or category.'); return; }
    list.textContent = '';
    matches.forEach(function (pkg) {
      var card = element('article', 'package-card'), header = element('header'), image = document.createElement('img'), heading = element('div');
      image.src = 'CydiaIcon.png'; image.alt = ''; heading.appendChild(element('h3', '', pkg.name)); heading.appendChild(element('small', '', pkg.version)); header.appendChild(image); header.appendChild(heading); card.appendChild(header);
      card.appendChild(element('p', '', pkg.description.split('\n')[0])); var foot = element('div', 'card-foot'); foot.appendChild(element('span', 'badge', pkg.section));
      var link = element('a', 'text-link', 'View package ↗'); link.href = 'package.html?id=' + encodeURIComponent(pkg.id); foot.appendChild(link); card.appendChild(foot); list.appendChild(card);
    });
  }
  query.addEventListener('input', render);
  Array.prototype.forEach.call(document.querySelectorAll('[data-filter]'), function (button) { button.addEventListener('click', function () {
    filter = button.getAttribute('data-filter'); Array.prototype.forEach.call(document.querySelectorAll('[data-filter]'), function (b) { var active = b === button; b.classList.toggle('selected', active); b.setAttribute('aria-pressed', String(active)); }); render();
  }); });
  fetch('packages.json').then(function (response) { if (!response.ok) throw new Error('Package index unavailable'); return response.json(); }).then(function (data) { if (!Array.isArray(data)) throw new Error('Invalid catalog'); packages = data; loaded = true; render(); }).catch(function () {
    document.getElementById('package-count').textContent = 'Couldn’t load packages'; message('Couldn’t load the tweaks.', 'Try refreshing the page, or have a look on GitHub.', 'View on GitHub ↗', 'https://github.com/realphoni/phoni-repo/tree/main/debs');
  });
}());
