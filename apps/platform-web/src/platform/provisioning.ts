export function downloadProvisioningFile(credential: string) {
  const blob = new Blob([`${credential}\n`], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = "edge_device_provision.txt";
  anchor.click();
  URL.revokeObjectURL(url);
}
