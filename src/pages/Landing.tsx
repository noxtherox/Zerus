import { useEffect } from "react";
import {
  ArrowRight,
  Check,
  Download,
  FileText,
  Folder,
  Github,
  Link2,
  Menu,
  Search,
  Sparkles,
  TerminalSquare,
  X,
} from "@/lib/icons";
import { ZerusLogo } from "@/components/ZerusLogo";
import "./Landing.css";

const DOWNLOAD_URL = "/api/download";
const RELEASES_URL = "https://github.com/noxtherox/Zerus/releases/latest";
const REPOSITORY_URL = "https://github.com/noxtherox/Zerus";

const features = [
  {
    number: "01",
    title: "Files, not a format",
    description:
      "Every note is a Markdown file inside a folder you choose. Open it with Zerus, a text editor, or tools that have not been invented yet.",
    icon: FileText,
  },
  {
    number: "02",
    title: "Structure without friction",
    description:
      "Folders become note types. YAML becomes useful properties. Wikilinks and backlinks connect the details without hiding how anything works.",
    icon: Link2,
  },
  {
    number: "03",
    title: "Made for real work",
    description:
      "Search, filters, linked files, live Markdown preview, and an embedded terminal keep research and execution in the same calm workspace.",
    icon: TerminalSquare,
  },
];

const faqs = [
  {
    question: "Where are my notes stored?",
    answer:
      "In a normal folder on your Mac. Zerus reads and writes Markdown directly, so your vault stays portable and easy to back up.",
  },
  {
    question: "Do I need an account?",
    answer:
      "No. Zerus is local-first and does not require an account, a subscription, or an internet connection to use your notes.",
  },
  {
    question: "Can I use my existing Markdown files?",
    answer:
      "Yes. Point Zerus at an existing folder or start a new vault. Your folders become types, while your Markdown stays readable everywhere.",
  },
];

export function Landing() {
  useEffect(() => {
    document.title = "Zerus — Notes that stay yours";
  }, []);

  return (
    <div className="landing-page">
      <header className="landing-nav">
        <a className="landing-brand" href="#top" aria-label="Zerus home">
          <ZerusLogo className="landing-brand-mark" />
          <span>Zerus</span>
        </a>

        <nav className="landing-nav-links" aria-label="Main navigation">
          <a href="#principles">Why Zerus</a>
          <a href="#features">Features</a>
          <a href="#questions">Questions</a>
        </nav>

        <a className="landing-nav-download" href={DOWNLOAD_URL}>
          Download <ArrowRight size={15} aria-hidden="true" />
        </a>
      </header>

      <main id="top">
        <section className="landing-hero" aria-labelledby="hero-title">
          <div className="landing-orbit landing-orbit-one" aria-hidden="true" />
          <div className="landing-orbit landing-orbit-two" aria-hidden="true" />

          <div className="landing-hero-copy">
            <p className="landing-eyebrow">
              <Sparkles size={14} aria-hidden="true" />
              Local-first notes for macOS
            </p>
            <h1 id="hero-title">
              Your notes should
              <span> outlive your notes app.</span>
            </h1>
            <p className="landing-hero-intro">
              Zerus turns an ordinary folder of Markdown files into a
              focused, connected knowledge base—without taking ownership of a
              single word.
            </p>
            <div className="landing-hero-actions">
              <a className="landing-button landing-button-primary" href={DOWNLOAD_URL}>
                <Download size={18} aria-hidden="true" />
                Download for macOS
              </a>
              <a className="landing-button landing-button-secondary" href="/app">
                Try the browser demo
                <ArrowRight size={17} aria-hidden="true" />
              </a>
            </div>
            <p className="landing-release-note">
              Free and open source <span aria-hidden="true">·</span> Apple silicon
            </p>
          </div>

          <ProductPreview />
        </section>

        <section className="landing-proof" aria-label="Product principles">
          <p>Plain Markdown</p>
          <span aria-hidden="true">◆</span>
          <p>No account</p>
          <span aria-hidden="true">◆</span>
          <p>Works offline</p>
          <span aria-hidden="true">◆</span>
          <p>Open source</p>
        </section>

        <section className="landing-principles" id="principles">
          <div className="landing-section-kicker">
            <span>THE LOCAL-FIRST DIFFERENCE</span>
            <span>001</span>
          </div>
          <div className="landing-principles-grid">
            <h2>Your folder is the database.</h2>
            <div>
              <p>
                No proprietary cloud. No export ritual. No anxiety about what
                happens when a service changes direction. Zerus works with
                the files already on your computer.
              </p>
              <ul className="landing-check-list">
                <li><Check aria-hidden="true" /> Sync with iCloud, Dropbox, Git, or anything else</li>
                <li><Check aria-hidden="true" /> Keep using your favorite editor and scripts</li>
                <li><Check aria-hidden="true" /> Back up, move, and inspect every part of your vault</li>
              </ul>
            </div>
          </div>
          <VaultDiagram />
        </section>

        <section className="landing-features" id="features">
          <div className="landing-section-heading">
            <p>BUILT TO DISAPPEAR</p>
            <h2>A notes app that gets out of your way.</h2>
          </div>
          <div className="landing-feature-grid">
            {features.map(({ number, title, description, icon: Icon }) => (
              <article className="landing-feature-card" key={title}>
                <div className="landing-feature-topline">
                  <span>{number}</span>
                  <Icon size={22} strokeWidth={1.6} aria-hidden="true" />
                </div>
                <h3>{title}</h3>
                <p>{description}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="landing-workflow">
          <div className="landing-workflow-copy">
            <p className="landing-eyebrow landing-eyebrow-dark">A quiet power tool</p>
            <h2>Think in notes.<br />Work in files.</h2>
            <p>
              Write with live Markdown formatting, move through linked ideas,
              attach the documents that matter, then open a terminal in the
              exact folder you are already working in.
            </p>
            <a href="/app">
              Explore the browser demo <ArrowRight size={17} aria-hidden="true" />
            </a>
          </div>
          <div className="landing-command-card" aria-label="Zerus command example">
            <div className="landing-command-titlebar">
              <span /><span /><span />
              <p>zerus — research</p>
            </div>
            <div className="landing-command-content">
              <p><span>$</span> zerus search <em>"local-first"</em></p>
              <div className="landing-command-result">
                <p>3 notes found</p>
                <strong>Principles / Local-first software.md</strong>
                <strong>Research / Durable tools.md</strong>
                <strong>Ideas / Files over feeds.md</strong>
              </div>
              <p className="landing-command-cursor"><span>$</span> <i /></p>
            </div>
          </div>
        </section>

        <section className="landing-faq" id="questions">
          <div>
            <p className="landing-section-label">GOOD TO KNOW</p>
            <h2>Questions, answered plainly.</h2>
          </div>
          <div className="landing-faq-list">
            {faqs.map((faq) => (
              <details key={faq.question}>
                <summary>
                  {faq.question}
                  <span aria-hidden="true"><Menu className="faq-menu-icon" /><X className="faq-close-icon" /></span>
                </summary>
                <p>{faq.answer}</p>
              </details>
            ))}
          </div>
        </section>

        <section className="landing-final-cta">
          <ZerusLogo className="landing-final-mark" />
          <p>YOUR NOTES. YOUR FILES. YOUR SYSTEM.</p>
          <h2>Make your knowledge durable.</h2>
          <div className="landing-hero-actions">
            <a className="landing-button landing-button-primary" href={DOWNLOAD_URL}>
              <Download size={18} aria-hidden="true" />
              Download Zerus
            </a>
            <a className="landing-button landing-button-secondary" href={REPOSITORY_URL}>
              <Github size={18} aria-hidden="true" />
              View on GitHub
            </a>
          </div>
        </section>
      </main>

      <footer className="landing-footer">
        <a className="landing-brand" href="#top">
          <ZerusLogo className="landing-brand-mark" />
          <span>Zerus</span>
        </a>
        <p>Local-first notes, made with care.</p>
        <div>
          <a href={REPOSITORY_URL}>GitHub</a>
          <a href={RELEASES_URL}>Releases</a>
        </div>
      </footer>
    </div>
  );
}

function ProductPreview() {
  return (
    <div className="landing-product" aria-label="Preview of the Zerus notes app">
      <div className="landing-product-titlebar">
        <div><span /><span /><span /></div>
        <p>Zerus</p>
        <span />
      </div>
      <div className="landing-product-body">
        <aside className="landing-product-sidebar">
          <ZerusLogo className="landing-product-logo" />
          <nav aria-label="Example vault folders">
            <a className="is-active"><Folder /> Notes <span>12</span></a>
            <a><span className="folder-icon">◈</span> Projects <span>6</span></a>
            <a><span className="folder-icon">✦</span> Ideas <span>18</span></a>
            <a><span className="folder-icon">◎</span> People <span>9</span></a>
          </nav>
        </aside>
        <div className="landing-product-list">
          <div className="landing-product-search"><Search /> Search notes…</div>
          <div className="landing-note-row is-selected">
            <strong>Tools that last</strong><p>Software should respect the artifacts…</p><span>Today</span>
          </div>
          <div className="landing-note-row">
            <strong>Local-first principles</strong><p>Ownership begins with files you can…</p><span>Yesterday</span>
          </div>
          <div className="landing-note-row">
            <strong>A calmer workspace</strong><p>Notes, documents, and commands in…</p><span>Mon</span>
          </div>
        </div>
        <article className="landing-product-editor">
          <div className="landing-product-toolbar">
            <span>B</span><i>I</i><span>H₁</span><span>H₂</span><span>☷</span><span>↗</span>
          </div>
          <div className="landing-product-document">
            <p className="landing-document-type">PRINCIPLES</p>
            <h3>Tools that last</h3>
            <p>
              The best tools leave you with something <mark>you still own</mark>.
              A folder. A file. A body of work that remains useful on its own.
            </p>
            <blockquote>
              Your knowledge should be more durable than the software used to shape it.
            </blockquote>
            <h4>Working principles</h4>
            <p className="landing-document-check"><Check /> Plain text by default</p>
            <p className="landing-document-check"><Check /> Connections without lock-in</p>
          </div>
        </article>
      </div>
    </div>
  );
}

function VaultDiagram() {
  return (
    <div className="landing-vault-diagram">
      <div className="landing-vault-root">
        <Folder aria-hidden="true" />
        <div><strong>My Zerus</strong><span>A normal folder on your Mac</span></div>
      </div>
      <div className="landing-vault-branches">
        <div><Folder /><strong>Projects</strong><span>Folders become note types</span></div>
        <div><FileText /><strong>Ideas.md</strong><span>Notes stay plain Markdown</span></div>
        <div><Link2 /><strong>[[Connections]]</strong><span>Links stay readable</span></div>
        <div><Github /><strong>git push</strong><span>Use the tools you trust</span></div>
      </div>
    </div>
  );
}
