/*
 * Interactive quiz widget for the Agent-First Engineering curriculum.
 * Renders a phase's quiz.json into a clickable self-test: pick an option,
 * get immediate feedback (correct/incorrect + explanation + source), live score.
 * Pure vanilla JS, no deps. Single source of truth = the same quiz.json the
 * check-understanding skill reads. Works on static hosting (GitHub Pages).
 */
(function () {
  "use strict";

  function shuffle(a) {
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  function el(tag, cls, txt) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }

  // Resolve quiz.json robustly regardless of use_directory_urls / base path.
  async function loadQuiz(src, base) {
    const tried = [];
    const candidates = [src, "../quiz.json", "quiz.json"];
    for (const c of candidates) {
      if (!c || tried.indexOf(c) !== -1) continue;
      tried.push(c);
      try {
        const res = await fetch(new URL(c, base).href);
        if (res.ok) return await res.json();
      } catch (e) { /* try next */ }
    }
    throw new Error("quiz data not found");
  }

  function renderQuiz(container, data) {
    const phaseNum = parseInt(data.phase, 10);
    const state = { difficulty: "all", total: 0, answered: 0, correct: 0 };

    container.innerHTML = "";

    const header = el("div", "quiz-header");
    header.appendChild(el("h2", "quiz-title", data.title ? "Quiz — " + data.title : "Check your understanding"));
    const score = el("div", "quiz-score");
    header.appendChild(score);
    container.appendChild(header);

    container.appendChild(el("p", "quiz-intro", "Pick an answer to see if you're right, with the explanation and a source. Your score updates as you go."));

    const filter = el("div", "quiz-filter");
    ["all", "easy", "medium", "hard"].forEach(function (d) {
      const b = el("button", "quiz-filter-btn" + (d === "all" ? " active" : ""), d === "all" ? "All" : d.charAt(0).toUpperCase() + d.slice(1));
      b.type = "button";
      b.addEventListener("click", function () {
        state.difficulty = d;
        filter.querySelectorAll("button").forEach(function (x) { x.classList.remove("active"); });
        b.classList.add("active");
        build();
      });
      filter.appendChild(b);
    });
    container.appendChild(filter);

    const list = el("div", "quiz-list");
    container.appendChild(list);

    const footer = el("div", "quiz-footer");
    const reset = el("button", "quiz-reset", "↻ Shuffle & retry");
    reset.type = "button";
    reset.addEventListener("click", build);
    footer.appendChild(reset);
    if (!isNaN(phaseNum)) {
      const note = el("p", "quiz-skillnote");
      note.innerHTML = "Prefer an agent-driven, one-at-a-time version? Run <code>/check-understanding " + phaseNum + "</code> in Claude Code.";
      footer.appendChild(note);
    }
    container.appendChild(footer);

    function updateScore() {
      score.textContent = state.answered + " / " + state.total + " answered · " + state.correct + " correct";
    }

    function build() {
      state.correct = 0;
      state.answered = 0;
      let qs = data.questions.slice();
      if (state.difficulty !== "all") qs = qs.filter(function (q) { return q.difficulty === state.difficulty; });
      qs = shuffle(qs);
      state.total = qs.length;
      list.innerHTML = "";
      updateScore();

      qs.forEach(function (q, qi) {
        const card = el("div", "quiz-q");
        const meta = el("div", "quiz-q-meta");
        meta.appendChild(el("span", "quiz-badge quiz-" + q.difficulty, q.difficulty));
        if (q.lesson) meta.appendChild(el("span", "quiz-lesson", q.lesson));
        card.appendChild(meta);
        card.appendChild(el("p", "quiz-q-text", (qi + 1) + ". " + q.question));

        const opts = shuffle(q.options.map(function (text, idx) { return { text: text, idx: idx }; }));
        const optWrap = el("div", "quiz-opts");
        let locked = false;

        opts.forEach(function (o) {
          const btn = el("button", "quiz-opt", o.text);
          btn.type = "button";
          btn.addEventListener("click", function () {
            if (locked) return;
            locked = true;
            state.answered++;
            const isCorrect = o.idx === q.answer;
            if (isCorrect) state.correct++;

            optWrap.querySelectorAll(".quiz-opt").forEach(function (b, bi) {
              b.disabled = true;
              if (opts[bi].idx === q.answer) b.classList.add("correct");
            });
            if (!isCorrect) btn.classList.add("incorrect");

            const exp = el("div", "quiz-explain " + (isCorrect ? "ok" : "no"));
            exp.appendChild(el("span", "quiz-verdict", isCorrect ? "✓ Correct" : "✗ Not quite"));
            exp.appendChild(el("p", "quiz-explain-text", q.explanation || ""));
            if (q.citations && q.citations.length) {
              const cite = el("p", "quiz-cite");
              cite.appendChild(document.createTextNode("↳ "));
              const a = el("a", null, "source");
              a.href = q.citations[0];
              a.target = "_blank";
              a.rel = "noopener";
              cite.appendChild(a);
              exp.appendChild(cite);
            }
            card.appendChild(exp);
            updateScore();
          });
          optWrap.appendChild(btn);
        });

        card.appendChild(optWrap);
        list.appendChild(card);
      });
    }

    build();
  }

  async function init() {
    const containers = document.querySelectorAll(".quiz-app");
    for (const c of containers) {
      if (c.dataset.loaded) continue;
      c.dataset.loaded = "1";
      try {
        const data = await loadQuiz(c.dataset.quiz, window.location.href);
        renderQuiz(c, data);
      } catch (e) {
        const raw = c.dataset.quiz || "../quiz.json";
        c.innerHTML = '<p>Could not load the quiz. <a href="' + raw + '">View the raw questions</a>.</p>';
      }
    }
  }

  // Material's instant navigation exposes document$; fall back to DOMContentLoaded.
  if (window.document$ && typeof window.document$.subscribe === "function") {
    window.document$.subscribe(init);
  } else if (document.readyState !== "loading") {
    init();
  } else {
    document.addEventListener("DOMContentLoaded", init);
  }
})();
