// UI Components
function Button(label) {
  return `<button class="accent">${label}</button>`;
}

function Card(title, content) {
  return `<div class="card"><h3>${title}</h3><p>${content}</p></div>`;
}

module.exports = { Button, Card };
