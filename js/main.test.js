const { add, multiply, randomSuccess } = require('./main');

describe('Math functions', () => {
  test('add function works correctly', () => {
    expect(add(2, 3)).toBe(5);
    expect(add(-1, 1)).toBe(0);
    expect(add(0, 0)).toBe(0);
  });

  test('multiply function works correctly', () => {
    expect(multiply(2, 3)).toBe(6);
    expect(multiply(-2, 3)).toBe(-6);
    expect(multiply(0, 5)).toBe(0);
  });

  test('flaky test that fails 1 in 5 times', () => {
    const result = randomSuccess();
    expect(result).toBe(true);
  });
});