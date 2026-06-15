export const meta = {
  name: 'upstream-merge-review',
  description: 'Map and review upstream/main merge risks for the Hermes fork',
  phases: [
    { title: 'Broad Search', detail: 'Composer scans upstream and fork-only changes for overlap risk' },
    { title: 'Brain Review', detail: 'Codex and Claude independently review merge hazards and test focus' },
    { title: 'Synthesis', detail: 'Codex synthesizes the merge checklist and risk map' },
  ],
}

const BROAD_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['summary', 'risk_areas', 'recommended_tests'],
  properties: {
    summary: { type: 'string' },
    risk_areas: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['area', 'files', 'risk', 'why', 'merge_advice'],
        properties: {
          area: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          risk: { type: 'string', enum: ['low', 'medium', 'high'] },
          why: { type: 'string' },
          merge_advice: { type: 'string' },
        },
      },
    },
    recommended_tests: { type: 'array', items: { type: 'string' } },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['summary', 'blockers', 'preserve_local', 'test_plan'],
  properties: {
    summary: { type: 'string' },
    blockers: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'files', 'severity', 'evidence', 'fix'],
        properties: {
          title: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          severity: { type: 'string', enum: ['low', 'medium', 'high', 'critical'] },
          evidence: { type: 'string' },
          fix: { type: 'string' },
        },
      },
    },
    preserve_local: { type: 'array', items: { type: 'string' } },
    test_plan: { type: 'array', items: { type: 'string' } },
  },
}

const SYNTH_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['merge_strategy', 'highest_risks', 'must_preserve', 'verification_commands'],
  properties: {
    merge_strategy: { type: 'string' },
    highest_risks: { type: 'array', items: { type: 'string' } },
    must_preserve: { type: 'array', items: { type: 'string' } },
    verification_commands: { type: 'array', items: { type: 'string' } },
  },
}

const cfg = args || {}
const base = cfg.base || 'HEAD'
const upstream = cfg.upstream || 'upstream/main'

phase('Broad Search')
const broadPrompt = `
You are doing the broad search pass for a Hermes fork upstream merge.
Working directory is the repository root. Inspect with git/read-only commands only; do not edit files.

Task:
- Compare local fork ${base} against ${upstream}.
- Find areas where upstream changed files that the fork also changed or relies on.
- Pay special attention to desktop realtime voice, desktop slash/cwd behavior, CI publish guards, gateway Signal/Anthropic OAuth/media safety patches, and update/autostash tests.
- Use commands like:
  git rev-list --left-right --count ${base}...${upstream}
  git log --oneline ${base}..${upstream}
  git log --oneline ${upstream}..${base}
  git diff --name-status ${base}...${upstream}
  git diff --name-only ${upstream}..${base}
  git diff ${upstream}..${base} -- <locally changed files>

Return concrete merge risks and focused tests.
`

const broad = await agent(broadPrompt, {
  provider: 'pi',
  model: 'cursor/composer-2.5',
  sandbox: 'danger-full-access',
  label: 'composer-broad-scan',
  schema: BROAD_SCHEMA,
  key: 'composer-broad-scan',
})

phase('Brain Review')
const codexPrompt = `
You are the Codex merge reviewer for a Hermes fork. Inspect the repository read-only.
Inputs from Composer:
${JSON.stringify(broad, null, 2)}

Independently verify the claimed risks. Focus on semantic merge hazards between local fork-only changes and ${upstream}.
Return only concrete blockers/risks that should affect the merge or verification plan.
`

const claudePrompt = `
You are the Claude Code merge reviewer for a Hermes fork. Inspect the repository read-only.
Inputs from Composer:
${JSON.stringify(broad, null, 2)}

Independently verify the claimed risks. Look especially for areas where upstream rewrites could silently drop fork behavior even when git conflicts are absent.
Return only concrete blockers/risks that should affect the merge or verification plan.
`

const reviews = await parallel([
  () => agent(codexPrompt, {
    provider: 'codex',
    effort: 'high',
    sandbox: 'read-only',
    label: 'codex-merge-review',
    schema: REVIEW_SCHEMA,
    key: 'codex-merge-review',
  }),
  () => agent(claudePrompt, {
    provider: 'claude-code',
    effort: 'high',
    sandbox: 'read-only',
    label: 'claude-merge-review',
    schema: REVIEW_SCHEMA,
    key: 'claude-merge-review',
  }),
])

phase('Synthesis')
const synthesis = await agent(`
Synthesize a practical merge strategy from these independent reviews.
Composer broad scan:
${JSON.stringify(broad, null, 2)}

Codex/Claude reviews:
${JSON.stringify(reviews.filter(Boolean), null, 2)}

Output a concise checklist for the human/operator who will actually merge ${upstream} into ${base}.
`, {
  provider: 'codex',
  effort: 'medium',
  sandbox: 'read-only',
  label: 'codex-synthesis',
  schema: SYNTH_SCHEMA,
  key: 'codex-synthesis',
})

return {
  broad,
  reviews: reviews.filter(Boolean),
  synthesis,
}
