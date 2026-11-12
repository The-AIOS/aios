// Triage for new issues and PRs (#260): likely duplicates across the org, the work in
// flight, and a transfer suggestion when the issue looks like it belongs elsewhere.
//
// It only ever COMMENTS (or, in dry-run, writes the job summary). It never closes, labels,
// edits or transfers anything: a maintainer makes every call. tests/triage-action.test.sh
// fails if a call that changes an issue's state, labels or repo appears in this file.
//
// Pure functions are exported for the test; run() is what the workflow calls through
// actions/github-script.

const ORG = 'The-AIOS';
const MARKER = '<!-- aios-triage -->';
const IN_FLIGHT = 'https://github.com/search?q=org%3AThe-AIOS+is%3Aopen+label%3A%22status%3A+in-progress%22&type=issues';
const ROUTING = 'https://github.com/The-AIOS/aios/blob/main/CONTRIBUTING.md#which-repo--four-repos-and-the-question-that-actually-routes-you';

const STOP = new Set(('a an and are as at be but by can do does for from has have how i if in into is it its ' +
  'my no not of on or so that the their them then there this to too was we what when where which who why ' +
  'will with you your after before still only now one every each more less than when while about').split(' '));

// What-you-observed signals, from CONTRIBUTING § Which repo?, matched as whole words or
// phrases (never inside another word: "pane" must not match "panel", nor "window"
// "Windows"). Each is weak alone; a suggestion needs two signals for another repo and
// more than the current repo has. Generic words ("install", "window") are left out on
// purpose: core issues use them as often as App issues do.
const SIGNALS = {
  'aios-app': ['installer', 'first-run', 'setup window', 'packaging', 'dmg', 'exe', 'appimage', 'the app',
               'aios app', 'desktop app', 'sidebar', 'tab group', 'chat view', 'session pane', 'menu bar'],
  'aios-glass': ['glass', 'panel', 'vs code', 'vscode', 'antigravity', 'cursor', 'open vsx', 'ide extension'],
  'site': ['the-aios.com', 'website', 'web site', 'landing page', 'llms.txt', 'the site'],
  'aios': ['/aios:', 'command', 'agent', 'skill', 'hook', 'hooks', 'template', 'claude.md', 'changelog', 'vault',
           'user.md', 'intent.md', 'mcp', 'spawn', 'setup.md', 'windows', 'aios-commit', 'context floor'],
};

function hasWord(text, phrase) {
  const esc = phrase.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
  return new RegExp(`(^|[^a-z0-9-])${esc}($|[^a-z0-9-])`, 'i').test(text);
}

function keywords(title) {
  return [...new Set(String(title || '').toLowerCase()
    .replace(/[`"'()[\]{}<>:,.!?;]/g, ' ')
    .split(/\s+/)
    .filter(w => w.length > 2 && !STOP.has(w) && !/^\d+$/.test(w)))].slice(0, 6);
}

function scores(text) {
  const t = String(text || '').toLowerCase();
  const out = {};
  for (const [repo, words] of Object.entries(SIGNALS)) out[repo] = words.filter(w => hasWord(t, w)).length;
  return out;
}

// A matched issue's title goes into a public comment: neutralise mentions and markup so
// quoting it can never ping anyone or break the comment.
function safeTitle(t) {
  return String(t || '').replace(/[`<>]/g, '').replace(/@/g, '@\u200b').slice(0, 120);
}

function suggestRepo(text, currentRepo) {
  const s = scores(text);
  let best = null;
  for (const [repo, n] of Object.entries(s)) {
    if (repo === currentRepo) continue;
    if (n >= 2 && n > (s[currentRepo] || 0) && (!best || n > s[best])) best = repo;
  }
  return best;
}

function buildComment({ matches, suggestion }) {
  if (!matches.length && !suggestion) return '';
  const lines = [MARKER, 'Thanks for opening this. An automatic first look, to help it land in the right place:', ''];
  if (matches.length) {
    lines.push('**Possibly related, already open or recently closed:**');
    for (const m of matches) lines.push(`- ${m.repo}#${m.number} ${safeTitle(m.title)}${m.state === 'closed' ? ' (closed)' : ''}`);
    lines.push('', `If one of these is the same thing, a comment there keeps the work in one place. Also see the [work in flight](${IN_FLIGHT}).`);
  }
  if (suggestion) {
    lines.push('', `**This may belong in The-AIOS/${suggestion}** (see [Which repo?](${ROUTING})). A maintainer will move it if so.`);
  }
  lines.push('', '_This bot only comments. It never closes, labels or moves anything; a maintainer decides._');
  return lines.join('\n');
}

async function run({ github, context, core }) {
  const item = context.payload.issue || context.payload.pull_request;
  if (!item) return;
  const repo = context.repo.repo;
  const kind = context.payload.issue ? 'issue' : 'pr';

  const words = keywords(item.title);
  let matches = [];
  if (words.length >= 2) {
    const q = `org:${ORG} ${words.join(' ')} in:title`;
    let res;
    try {
      res = await github.rest.search.issuesAndPullRequests({ q, per_page: 10 });
    } catch (e) {
      // A search the API rejects must never fail the check on a stranger's issue or PR.
      core.info(`search failed (${e.status || ''} ${e.message}); staying quiet`);
      return;
    }
    matches = res.data.items
      .filter(i => i.number !== item.number || !i.repository_url.endsWith(`/${repo}`))
      .slice(0, 5)
      .map(i => ({ repo: i.repository_url.split('/').pop(), number: i.number, title: i.title, state: i.state }));
  }
  const suggestion = kind === 'issue' ? suggestRepo(`${item.title}\n${item.body || ''}`, repo) : null;
  const body = buildComment({ matches, suggestion });
  if (!body) { core.info('nothing matched; staying quiet'); return; }

  const mode = (process.env.TRIAGE_MODE || 'dry-run').toLowerCase();
  if (mode !== 'comment') {
    await core.summary.addHeading(`Triage (dry run) for #${item.number}`).addRaw(body).write();
    core.info('dry run: wrote the job summary, posted nothing');
    return;
  }
  const existing = await github.rest.issues.listComments({ ...context.repo, issue_number: item.number, per_page: 100 });
  if (existing.data.some(c => (c.body || '').includes(MARKER))) { core.info('already commented'); return; }
  await github.rest.issues.createComment({ ...context.repo, issue_number: item.number, body });
}

module.exports = { keywords, scores, suggestRepo, buildComment, safeTitle, run, MARKER };
