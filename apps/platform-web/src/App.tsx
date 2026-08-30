import { HomePage } from "./pages/HomePage";
import { LocaleProvider } from "./lib/i18n";

export function App() {
  return <LocaleProvider><HomePage /></LocaleProvider>;
}
