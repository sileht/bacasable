function add(a, b) {
  return a + b;
}

function multiply(a, b) {
  return a * b;
}

function randomSuccess() {
  return Math.random() > 0.2;
}

module.exports = {
  add,
  multiply,
  randomSuccess
};