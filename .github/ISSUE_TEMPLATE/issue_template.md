---
name: Bioconductor Package Submission
title: ""
labels: ""
assignees: ""
---

Update the following URL to point to the GitHub repository of the package you
wish to submit to _Bioconductor_.

- Repository: https://github.com/yourusername/yourpackagename

Optional automation input:

- Branch/Ref: devel

Confirm the following by editing each check box to `[x]`:

- [ ] I understand that by submitting my package to _Bioconductor_, the package
  source and all review commentary are visible to the general public.

- [ ] I have read the _Bioconductor_ [Package Submission][2] instructions. My
  package is consistent with the _Bioconductor_ [Package Guidelines][1].

- [ ] I understand Bioconductor [Package Naming Policy][9] and acknowledge
  Bioconductor may retain use of package name.

- [ ] I understand that a minimum requirement for package acceptance is to pass
  R CMD check and R CMD BiocCheck with no ERROR or WARNINGS. Passing these
  checks does not result in automatic acceptance. The package will then undergo
  a formal review and recommendations for acceptance regarding other
  Bioconductor standards will be addressed.

- [ ] My package addresses statistical or bioinformatic issues related to the
  analysis and comprehension of high throughput genomic data.

- [ ] I am committed to the long-term maintenance of my package. This includes
  monitoring the [support site][3] for issues users may have, subscribing to
  the [bioc-devel][4] mailing list, and responding promptly to Core team update
  requests.

- [ ] I understand it is my responsibility to maintain a valid, active
  maintainer email in DESCRIPTION and allow notifications from
  noreply@bioconductor.org and BBS-noreply@bioconductor.org.

- [ ] I am familiar with the [Bioconductor code of conduct][7] and agree to
  abide by it.

I am familiar with essential _Bioconductor_ software management aspects,
including:

- [ ] The `devel` branch for new packages and features.
- [ ] The stable `release` branch, made available every six months, for bug
      fixes.
- [ ] _Bioconductor_ version control using [Git][5] (optionally
  [via GitHub][6]).

For questions/help about submission, including automatic report output, please
use the #package-submission channel in Bioconductor Community Slack.

---

### AI Review Assistant Activation

After verifying this issue is complete and correctly formatted, a **repository
collaborator** should add the **`AI review`** label to initiate the AI-assisted
review system:

1. `build-check.yml` runs R CMD check, BiocCheck, and test coverage
2. Build/check results are posted to this issue
3. `auto-review.yml` generates and posts a preliminary AI-assisted review

**Note:** Co-dependent remotes are NOT supported on initial runs (see below).

---

### Rerunning with Co-dependent Packages

To rerun the full workflow chain, post a comment starting with `@biocreview`:

```
@biocreview
```

If the package depends on GitHub packages not yet on Bioconductor/CRAN
(e.g., simultaneous submissions), include a `Remotes:` line:

```
@biocreview
Remotes: waldronlab/imageTCGAutils, waldronlab/HistoImagePlot
```

**Important:**
- `Remotes:` can ONLY be specified in `@biocreview` rerun comments
- Remotes are NOT supported on initial runs (when adding the AI review label)
- Do NOT put `Remotes:` in the issue body above

---

### Common Formatting Mistakes (please avoid)

- Missing or malformed `Repository:` URL
- `Repository:` pointing to a private repository
- Attempting to use `Remotes:` on initial run or in issue body
- `Remotes:` not in `owner/repo` format

[1]: https://contributions.bioconductor.org/
[2]: https://bioconductor.org/developers/package-submission/
[3]: https://support.bioconductor.org
[4]: https://stat.ethz.ch/mailman/listinfo/bioc-devel
[5]: http://bioconductor.org/developers/how-to/git/
[6]: http://bioconductor.org/developers/how-to/git/sync-existing-repositories/
[7]: https://bioconductor.org/about/code-of-conduct/
[8]: https://bioconductor.org/
[9]: https://bioconductor.org/developers/package-submission/#naming
