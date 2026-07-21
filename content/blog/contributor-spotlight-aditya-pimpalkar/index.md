---
title: "Contributor Spotlight: Aditya Pimpalkar"
date: 2026-07-21T06:00:00
draft: false
image:
    url: aditya-blog-cover.png
    attribution:
authors:
  - spron-in
tags:
  - community
  - open-source
  - spotlight
  - kubernetes
  - databases
summary: "Meet Aditya Pimpalkar — a freelance software engineer in Ireland who followed his curiosity about databases on Kubernetes into OpenEverest, and became one of the first to build against the v2 provider architecture."
---

Some contributors arrive with a database specialty. Aditya Pimpalkar arrived with a habit — chasing the tooling that makes other engineers faster — and let it lead him somewhere new.

<img src="aditya-headshot.jpeg" alt="OpenEverest Contributor - Aditya Pimpalkar photo" style="max-width: 480px; width: 100%; height: auto;">

Aditya is a freelance software engineer based in Ireland. Most recently he worked at Signify Health (part of the CVS Health Group), building Go micro-services and TypeScript SDKs — plus the day-to-day work that keeps teams shipping: auth and logging middleware, CI/CD with Docker, and observability through Grafana and Perses.

### The pull toward developer tools

Aditya's open-source story started while he was finishing his master's thesis, with contributions to [Twenty](https://github.com/twentyhq/twenty), the open-source CRM. The interest in developer tooling specifically clicked later, while integrating an application with Backstage. That experience pointed him toward platform engineering - the systems that make other engineers more effective — and it's a thread that runs through most of his work since: clearer APIs, better dashboards, and tooling that removes friction rather than adding it. Along the way he's contributed to projects like [HyperDX](https://github.com/hyperdxio/hyperdx) and [Perses](https://github.com/perses/perses) (CNCF Sandbox), spanning frontend features and backend fixes.

### How he found OpenEverest

Databases on Kubernetes are a genuinely hard problem, and Aditya was looking for a project where he could learn that space while still shipping useful work. OpenEverest — a Kubernetes-native way to manage databases without locking teams into a single vendor — lined up with that curiosity.

"I'm still new to the Kubernetes side," he says, "but the problems are interesting and the community has been welcoming." So he's been contributing where he can and learning the codebase as he goes.

That's added up quickly. He wrote a guide on [running OpenEverest on GKE](https://openeverest.io/blog/running-openeverest-on-gke/), landed UI improvements in the console, and tracked down a provider-runtime bug — the kind of quiet fix that makes the platform more reliable for everyone.

### Early adopter of the v2 architecture

Aditya has also been one of the first to build against OpenEverest's v2 provider architecture, working on [provider-cloudnative-pg](https://github.com/AdityaPimpalkar/provider-cloudnative-pg) — a provider that provisions PostgreSQL HA clusters on Kubernetes via CloudNativePG. Early adopter work like that is exactly what a new SDK needs: it tests the design and surfaces gaps while the architecture is still taking shape.

### Beyond the terminal

On weekends, Aditya plays the tabla, an Indian classical percussion instrument. He performs at private home concerts, sometimes as an accompanist and sometimes as a soloist. It's a different kind of focus than debugging production systems, but the discipline rhymes: listen carefully, stay in time, and leave room for everyone else.

---

Welcome to the OpenEverest community, Aditya. Connect with him on [GitHub](https://github.com/adityapimpalkar), or say hello on the CNCF Slack — his handle there is **Aditya Pimpalkar**.

To get involved with OpenEverest yourself:

<div style="display:flex;gap:12px;margin-top:24px;flex-wrap:wrap;">
  <a href="https://cloud-native.slack.com/archives/C09RRGZL2UX" target="_blank" rel="noopener noreferrer" style="display:inline-flex;align-items:center;gap:8px;background-color:#4A154B;color:#fff;text-decoration:none;padding:10px 20px;border-radius:6px;font-weight:600;font-size:15px;">
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 122.8 122.8"><path d="M25.8 77.6c0 7.1-5.8 12.9-12.9 12.9S0 84.7 0 77.6s5.8-12.9 12.9-12.9h12.9v12.9zm6.5 0c0-7.1 5.8-12.9 12.9-12.9s12.9 5.8 12.9 12.9v32.3c0 7.1-5.8 12.9-12.9 12.9s-12.9-5.8-12.9-12.9V77.6z" fill="#e01e5a"/><path d="M45.2 25.8c-7.1 0-12.9-5.8-12.9-12.9S38.1 0 45.2 0s12.9 5.8 12.9 12.9v12.9H45.2zm0 6.5c7.1 0 12.9 5.8 12.9 12.9s-5.8 12.9-12.9 12.9H12.9C5.8 58.1 0 52.3 0 45.2s5.8-12.9 12.9-12.9h32.3z" fill="#36c5f0"/><path d="M97 45.2c0-7.1 5.8-12.9 12.9-12.9s12.9 5.8 12.9 12.9-5.8 12.9-12.9 12.9H97V45.2zm-6.5 0c0 7.1-5.8 12.9-12.9 12.9s-12.9-5.8-12.9-12.9V12.9C64.7 5.8 70.5 0 77.6 0s12.9 5.8 12.9 12.9v32.3z" fill="#2eb67d"/><path d="M77.6 97c7.1 0 12.9 5.8 12.9 12.9s-5.8 12.9-12.9 12.9-12.9-5.8-12.9-12.9V97h12.9zm0-6.5c-7.1 0-12.9-5.8-12.9-12.9s5.8-12.9 12.9-12.9h32.3c7.1 0 12.9 5.8 12.9 12.9s-5.8 12.9-12.9 12.9H77.6z" fill="#ecb22e"/></svg>
    Join Slack
  </a>
  <a href="https://github.com/openeverest/openeverest" target="_blank" rel="noopener noreferrer" style="display:inline-flex;align-items:center;gap:8px;background-color:#24292f;color:#fff;text-decoration:none;padding:10px 20px;border-radius:6px;font-weight:600;font-size:15px;">
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 16 16" fill="#fff"><path d="M8 .25a7.75 7.75 0 1 0 0 15.5A7.75 7.75 0 0 0 8 .25zm0 1.5a6.25 6.25 0 0 1 1.97 12.18c-.31.06-.42-.13-.42-.3v-1.05c0-.36-.01-1.02-.49-1.4 1.62-.18 2.5-.88 2.5-2.57 0-.57-.2-1.1-.53-1.49.05-.14.23-.7-.05-1.47 0 0-.44-.14-1.44.54a5.02 5.02 0 0 0-2.62 0C5.93 6.6 5.49 6.74 5.49 6.74c-.28.77-.1 1.33-.05 1.47-.33.39-.53.92-.53 1.49 0 1.69.88 2.39 2.5 2.57-.31.27-.43.67-.47 1.04-.42.19-1.5.52-2.16-.62 0 0-.39-.71-1.13-.76 0 0-.72-.01-.05.45 0 0 .48.23.82 1.08 0 0 .43 1.32 2.49.87v.75c0 .17-.11.36-.42.3A6.25 6.25 0 0 1 8 1.75z"/></svg>
    Star the Repo
  </a>
</div>