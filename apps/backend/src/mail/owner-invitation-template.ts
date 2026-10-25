export function ownerInvitationText(
  organization: string,
  url: string,
  expiresAt: Date,
) {
  return [
    'Vynic — მფლობელის მოწვევა / Owner invitation',
    '',
    `ორგანიზაცია / Organization: ${organization}`,
    'გახსენით ბმული ანგარიშის შესაქმნელად ან მოწვეულ ელფოსტაზე შესასვლელად.',
    'Open this link to create your account or sign in with the invited email address:',
    url,
    '',
    `ბმულის ვადა / Link expires: ${expiresAt.toISOString()} (UTC)`,
    'ეს ბმული პირადია. არ გააზიაროთ.',
    'This link is private. Do not forward it. If you did not expect this invitation, ignore this email.',
  ].join('\n');
}
