const FIELD_LIMITS = { title: [5, 120], description: [20, 4000], steps: [0, 2000], email: [0, 254] };

export function validateDraft(draft) {
  if (!['feedback', 'bug'].includes(draft.category)) return { field: 'category', message: 'Choose a report category.' };
  for (const [name, label] of [['title', 'subject'], ['description', 'description'], ['steps', 'steps to reproduce'], ['email', 'email']]) {
    if (typeof draft[name] !== 'string') return { field: name, message: `Check the ${label} field.` };
    const value = draft[name].trim();
    const [minimum, maximum] = FIELD_LIMITS[name];
    const needed = name === 'steps' && draft.category === 'bug' ? 10 : minimum;
    if (value.length < needed || value.length > maximum) {
      return { field: name, message: `Check the ${label} field. It must be ${needed} to ${maximum} characters.` };
    }
  }
  if (draft.email.trim() && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(draft.email.trim())) {
    return { field: 'email', message: 'Enter a valid email address or leave it blank.' };
  }
  return null;
}

function initializeForm() {
  const form = document.querySelector('#feedback-form');
  const category = form.elements.category;
  const steps = form.elements.steps;
  const submit = document.querySelector('#submit-feedback');
  const status = document.querySelector('#form-status');
  const verificationHint = document.querySelector('#verification-hint');
  let widgetId;
  let turnstileToken = '';
  let reportSent = false;

  const setStatus = (message, kind = '') => {
    status.textContent = message;
    status.className = `form-status${kind ? ` is-${kind}` : ''}`;
  };
  const clearFieldErrors = () => {
    form.querySelectorAll('[aria-invalid="true"]').forEach(field => {
      field.removeAttribute('aria-invalid');
      field.setAttribute('aria-describedby', field.getAttribute('aria-describedby').replace(/ form-status$/, ''));
    });
  };
  const showError = (message, field) => {
    setStatus(message, 'error');
    if (field) {
      field.setAttribute('aria-invalid', 'true');
      field.setAttribute('aria-describedby', `${field.getAttribute('aria-describedby')} form-status`);
      field.focus();
    } else {
      status.focus();
    }
  };
  const refreshCategory = () => {
    const isBug = category.value === 'bug';
    steps.required = isBug;
    steps.minLength = isBug ? 10 : 0;
    document.querySelector('#steps-required').hidden = !isBug;
  };
  const resetVerification = () => {
    turnstileToken = '';
    submit.disabled = true;
    verificationHint.textContent = 'Complete verification to send.';
    if (widgetId !== undefined) window.turnstile.reset(widgetId);
  };

  if (new URLSearchParams(location.search).get('category') === 'bug') category.value = 'bug';
  refreshCategory();
  category.addEventListener('change', refreshCategory);
  form.addEventListener('input', () => {
    clearFieldErrors();
    if (reportSent) {
      reportSent = false;
      setStatus(turnstileToken ? 'Ready to send.' : 'Complete verification to send.');
    }
  });

  form.addEventListener('submit', async event => {
    event.preventDefault();
    clearFieldErrors();
    const draft = {
      category: category.value,
      title: form.elements.title.value,
      description: form.elements.description.value,
      steps: steps.value,
      email: form.elements.email.value,
    };
    const problem = validateDraft(draft);
    if (problem) return showError(problem.message, form.elements[problem.field]);
    if (!turnstileToken) return showError('Complete verification before sending.');
    submit.disabled = true;
    setStatus('Sending your report…');
    try {
      const response = await fetch('/api/feedback', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...draft, turnstileToken }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'The report could not be sent. Try again.');
      form.reset();
      refreshCategory();
      reportSent = true;
      setStatus('Thank you. Your report was sent.', 'success');
      status.focus();
    } catch (error) {
      showError(error instanceof TypeError ? 'Network error. Please try again.' :
        error.message || 'The report could not be sent. Try again.');
    } finally {
      resetVerification();
    }
  });

  setStatus('Loading verification…');
  fetch('/api/feedback', { cache: 'no-store' })
    .then(async response => {
      if (!response.ok) throw new Error('Feedback is temporarily unavailable. Please try again later.');
      const config = await response.json();
      if (!config.siteKey) throw new Error('Feedback is temporarily unavailable. Please try again later.');
      return new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
        script.onload = resolve;
        script.onerror = reject;
        document.head.append(script);
      }).then(() => config.siteKey);
    })
    .then(siteKey => {
      widgetId = window.turnstile.render('#turnstile-widget', {
        sitekey: siteKey,
        action: 'feedback',
        theme: 'light',
        size: 'flexible',
        callback(token) {
          turnstileToken = token;
          submit.disabled = false;
          verificationHint.textContent = 'Verification complete.';
          if (!reportSent) setStatus('Ready to send.');
        },
        'expired-callback'() {
          resetVerification();
          verificationHint.textContent = 'Verification expired. Complete it again.';
          setStatus('Verification expired. Complete it again.', 'error');
        },
        'error-callback'() {
          turnstileToken = '';
          submit.disabled = true;
          verificationHint.textContent = 'Verification had a problem. Reload this page and try again.';
          setStatus('Verification had a problem. Reload this page and try again.', 'error');
          return true;
        },
      });
      setStatus('Complete verification to send.');
    })
    .catch(error => {
      verificationHint.textContent = 'Verification is unavailable.';
      setStatus(error.message || 'Feedback is temporarily unavailable. Please try again later.', 'error');
    });
}

if (typeof document !== 'undefined') initializeForm();
