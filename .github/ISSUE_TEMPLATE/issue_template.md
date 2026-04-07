---
name: Bioconductor Package Submission
about: AI-assisted package review for admission into Bioconductor
title: ""
labels: ""
assignees: ""
---

Update the following URL to point to the GitHub repository of the package you
wish to submit to _Bioconductor_.

- Repository: https://github.com/yourusername/yourpackagename

Optional automation input:

- Branch/Ref: devel

---

### AI Review Assistant Activation

After verifying this issue is complete and correctly formatted, a **repository
collaborator** should add the **`AI review`** label to initiate the AI-assisted
review system:

1. `build-check.yml` runs R CMD check, BiocCheck, and test coverage
2. Build/check results are posted to this issue
3. `auto-review.yml` generates and posts a preliminary AI-assisted review

**Note:** Co-dependent remotes are NOT supported on initial runs (see below).

You can re-run the AI review assistant by posting a comment starting with `@biocreview`.

---

### Rerunning with Co-dependent Packages Not Yet in Bioconductor/CRAN

Bioconductor packages can only depend, import, or suggest packages that are also available in Bioconductor or CRAN. If your package depends on GitHub packages not yet on Bioconductor/CRAN (e.g., simultaneous submissions), you can rerun the full workflow chain with pre-installed remotes by posting a comment starting as follows:

```
@biocreview
Remotes: username/package1, username/package2
```

**Important:**
- `Remotes:` can ONLY be specified in `@biocreview` rerun comments, NOT in the DESCRIPTION file.
- Remotes are NOT supported on initial runs (when adding the AI review label)
- Do NOT put `Remotes:` in the issue body above
- Use of remotes is only allowed during the review of multiple package submission. In the final accepted package, all dependencies must be on Bioconductor/CRAN. This is necessary for user friendliness, ensuring the package can be installed in a standard Bioconductor environment without additional setup, and that all packages meet CRAN/Bioconductor requirements and undergo continuous integration.

---

### Common Formatting Mistakes (please avoid)

- Missing or malformed `Repository:` URL
- `Repository:` pointing to a private repository

[1]: https://contributions.bioconductor.org/
[2]: https://bioconductor.org/developers/package-submission/
[3]: https://support.bioconductor.org
[4]: https://stat.ethz.ch/mailman/listinfo/bioc-devel
[5]: http://bioconductor.org/developers/how-to/git/
[6]: http://bioconductor.org/developers/how-to/git/sync-existing-repositories/
[7]: https://bioconductor.org/about/code-of-conduct/
[8]: https://bioconductor.org/
[9]: https://bioconductor.org/developers/package-submission/#naming
