// Utility functions
function formatDate(date) {
  return date.toISOString().split("T")[0];
}

function titleCase(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

module.exports = { formatDate, titleCase };
