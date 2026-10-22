import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

// Vitest is not running with global test APIs, so React Testing Library's
// automatic cleanup does not register itself. Without this, one test's page
// stays in the document and the next one sees two restaurants at once.
afterEach(cleanup);
