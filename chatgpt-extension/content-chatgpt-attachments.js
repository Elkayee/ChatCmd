globalThis.ChatCmdAttachments = Object.freeze({
  normalize(rawAttachments) {
    if (!Array.isArray(rawAttachments)) return [];
    return rawAttachments.flatMap((attachment, index) => {
      if (!attachment || typeof attachment !== 'object' || typeof attachment.content !== 'string' || !attachment.content) return [];
      const mimeType = String(attachment.mimeType || 'text/plain;charset=utf-8').toLowerCase();
      const rawName = String(attachment.name || `attachment-${index + 1}`).split(/[\\/]/).pop().trim();
      if (mimeType.startsWith('image/')) {
        const extension = mimeType.split(/[;/]/, 1)[0].split('/')[1]?.replace('jpeg', 'jpg') || 'png';
        const withoutTextSuffix = rawName.replace(/\.txt$/i, '');
        const name = withoutTextSuffix.includes('.') ? withoutTextSuffix : `${withoutTextSuffix || `image-${index + 1}`}.${extension}`;
        return [{ name, content: attachment.content, mimeType }];
      }
      const name = rawName.toLowerCase().endsWith('.txt') ? rawName : `${rawName || `pasted-text-${index + 1}`}.txt`;
      return [{ name, content: attachment.content, mimeType: 'text/plain;charset=utf-8' }];
    });
  },
  async attach(composer, rawAttachments, waitFor) {
    const attachments = this.normalize(rawAttachments);
    if (!attachments.length) return;
    const files = attachments.map((attachment) => {
      if (attachment.mimeType.startsWith('image/')) {
        const bytes = base64ToUint8Array(attachment.content);
        return new File([bytes], attachment.name, { type: attachment.mimeType, lastModified: Date.now() });
      }
      return new File([attachment.content], attachment.name, { type: attachment.mimeType, lastModified: Date.now() });
    });
    const input = findComposerFileInput(composer);
    if (input) assignFilesToInput(input, files);
    else pasteFilesIntoComposer(composer, files);
    await waitFor(
      () => {
        const hasTextMatch = files.every((file) => document.body?.textContent?.includes(file.name));
        const hasImageUpload = files.some((file) => file.type.startsWith('image/')) && !!document.querySelector('[data-testid*="attachment" i], [class*="attachment" i], img[alt], [aria-label*="attachment" i]');
        return (hasTextMatch || hasImageUpload) ? true : null;
      },
      12_000,
      `ChatGPT không xác nhận tệp đính kèm ${files.map((file) => file.name).join(', ')}.`,
    );
  },
});

function base64ToUint8Array(base64Data) {
  const cleanBase64 = base64Data.includes(',') ? base64Data.split(',')[1] : base64Data;
  const binaryString = atob(cleanBase64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < bytes.length; i++) bytes[i] = binaryString.charCodeAt(i);
  return bytes;
}

function findComposerFileInput(composer) {
  const form = composer.closest('form');
  const composerScope = composer.closest('[data-type="unified-composer"], [data-testid*="composer" i]');
  const scoped = [
    ...(form ? form.querySelectorAll('input[type="file"]') : []),
    ...(composerScope && composerScope !== form ? composerScope.querySelectorAll('input[type="file"]') : []),
  ].filter((input, index, items) => input instanceof HTMLInputElement && !input.disabled && items.indexOf(input) === index);
  const compatibleScoped = scoped.filter((input) => fileInputScore(input) > 0);
  if (compatibleScoped.length) return compatibleScoped.sort((left, right) => fileInputScore(right) - fileInputScore(left))[0];
  const explicit = [...document.querySelectorAll('input[type="file"][data-testid*="composer" i], input[type="file"][data-testid*="upload" i]')]
    .filter((input) => input instanceof HTMLInputElement && !input.disabled && fileInputScore(input) > 0);
  return explicit.sort((left, right) => fileInputScore(right) - fileInputScore(left))[0] || null;
}

function fileInputScore(input) {
  const accept = String(input.accept || '').toLowerCase();
  if (!accept || accept.includes('text') || accept.includes('.txt') || accept.includes('*/*') || accept.includes('image')) return 3 + (input.multiple ? 1 : 0);
  return 0;
}

function assignFilesToInput(input, files) {
  const transfer = new DataTransfer();
  for (const existing of input.files || []) transfer.items.add(existing);
  for (const file of files) transfer.items.add(file);
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files')?.set;
  if (setter) setter.call(input, transfer.files); else input.files = transfer.files;
  input.dispatchEvent(new Event('input', { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
}

function pasteFilesIntoComposer(composer, files) {
  const transfer = new DataTransfer();
  for (const file of files) transfer.items.add(file);
  const event = new ClipboardEvent('paste', { bubbles: true, cancelable: true, composed: true, clipboardData: transfer });
  composer.dispatchEvent(event);
}
