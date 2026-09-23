// Guard, run by `predev` and `prebuild`.
//
// web/static/data is a symlink to ../../data/processed. If it is missing or
// dangling — a checkout that did not restore symlinks, or a CI job that removed
// it without putting a real directory back — every fetch returns the SPA shell
// and the build cheerfully prerenders 389 pages of nothing. That failure is
// silent and looks like a data problem, so make it loud and look like what it
// is.

import { existsSync } from 'node:fs';
import { join } from 'node:path';

// One representative file rather than the directory: a dangling symlink still
// satisfies a directory check on some platforms, and an empty directory
// satisfies it everywhere.
const probe = join(process.cwd(), 'static', 'data', 'districts.json');

if (!existsSync(probe)) {
  console.error(`
web/static/data does not resolve.

  expected: ${probe}

It is a symlink to ../../data/processed, which is committed to the repo. Fix
with either:

  ln -s ../../data/processed web/static/data     # restore the symlink
  cp -R data/processed web/static/data           # or a real copy (CI does this)

See web/README.md.
`);
  process.exit(1);
}
