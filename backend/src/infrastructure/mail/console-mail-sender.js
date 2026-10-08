/**
 * Mail senders deliver email verification codes. The interface mirrors the SMS
 * sender: a single `send({ to, subject, body })`. When no sender is configured
 * (local/dev) the AuthService returns the code directly instead, exactly like
 * the SMS flow, so email signup can be exercised without a real provider.
 *
 * ConsoleMailSender is a safe default for development: it logs the message and
 * never contacts a provider. Production must inject a real sender (SMTP, SES,
 * etc.) — build one implementing the same `send` method.
 */
export class ConsoleMailSender {
  async send({ to, subject, body }) {
    console.info(`[mail] to=${to} subject=${JSON.stringify(subject)} body=${JSON.stringify(body)}`);
  }
}
