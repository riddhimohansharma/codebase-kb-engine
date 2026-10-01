export const theme = process.env.UI_THEME ?? "light";
export function Button(label: string): string {
  return `<button>${label}</button>`;
}
