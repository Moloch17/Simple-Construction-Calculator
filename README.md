# Simple Construction Calculator

Simple Construction Calculator is a Flutter app for fast construction and framing measurements using feet, inches, and fractional inches.

## How to use the calculator

1. Enter a number, then the feet sign (`'`).
2. Enter an operator.
3. Enter a number, then the inches sign (`"`).
4. Enter the fraction.

Example input:

- `1' 2" 3/4`
- `18' 11" 1/2 - 1" 1/2`

If units are left out, the app assumes the value is in inches.

## Input rules

- Use the format `number' number" fraction`
- Fractions are entered as values such as `1/2`, `3/4`, `5/16`
- Values without a foot or inch marker are treated as inches
- The result display can be tapped to open the calculation history
- Saved memory entries can be deleted by swiping right
