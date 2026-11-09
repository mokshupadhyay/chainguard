import js from "@eslint/js";
import ts from "typescript-eslint";
export default [{ ignores: ["dist"] }, js.configs.recommended, ...ts.configs.recommended,
  { rules: { "@typescript-eslint/no-explicit-any": "off", "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }] } }];
