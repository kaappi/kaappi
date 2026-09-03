# Upstream Zig: No LLM / No AI

Kaappi is written in Zig, so contributors routinely touch the Zig ecosystem —
filing compiler or standard-library bugs, reading the tracker, following
discussions. The Zig project enforces a **Strict No LLM / No AI Policy**, and
we respect it in full whenever we act in a Zig community space.

Canonical source:
<https://ziglang.org/code-of-conduct/#strict-no-llm-no-ai-policy>

## What the policy forbids

In Zig's own spaces — its issue tracker (hosted on Codeberg), the GitHub
mirror, Ziggit, and the forums — the policy forbids:

- LLM-generated content, whether code or prose;
- paraphrasing LLM-generated content;
- LLMs for editing, including fixing spelling or grammar;
- LLMs for translation (posting in your native language and letting readers
  translate is welcome; running it through a chatbot is not);
- sharing the results of LLM brainstorming, even when you write the prose;
- LLMs for finding bugs;
- talking about your use of chatbot/LLM services.

## What this means for Kaappi contributors

- **Nothing an LLM produced or touched goes upstream.** Issues, pull requests,
  comments, and forum posts to Zig must be entirely your own — including edits
  and translations.
- **LLM-found Zig bugs are not filed by the LLM.** If AI-assisted work on
  Kaappi turns up a likely Zig compiler or `std` bug, any upstream report must
  be your own independent investigation and your own words.
- **Don't discuss LLM/chatbot use in Zig spaces.**

## The boundary

This policy governs **contributions to Zig and its community**. It places no
restriction on AI-assisted work on *this* repository — Kaappi's own Zig code,
tests, and docs — which is our code under our own conventions (see
[claude-code-harness.md](claude-code-harness.md)). The line is the destination:
our repo, fine; Zig's spaces, off-limits.
