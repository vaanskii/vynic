import { Link } from "react-router-dom";
import { PageHeader, Panel } from "./components/Page";

export function NotFoundPage() {
  return (
    <>
      <PageHeader eyebrow="404" title="Page not found" description="This platform route does not exist." />
      <Panel><Link className="platform-text-link" to="/">Return to overview</Link></Panel>
    </>
  );
}
