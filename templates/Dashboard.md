---
title: Meridian dashboard
tags:
  - dashboard
---
# Meridian dashboard

> Cross-project view of Meridian tasks. Created once by `/mdn-init`; never overwritten, so edit it freely.
> Rendering depends on the Dataview plugin (not verified outside Obsidian).
> Archived tasks live in each project's `logs/` folder and are `[x]`, so `!completed` excludes them.

## Waiting for my review

```dataview
TASK FROM "meridian"
WHERE !completed AND contains(text, "status::review")
```

## Blocked

```dataview
TASK FROM "meridian"
WHERE !completed AND contains(text, "status::blocked")
```

## My open tasks

```dataview
TASK FROM "meridian"
WHERE !completed AND contains(text, "owner::me") AND (contains(text, "status::backlog") OR contains(text, "status::in-progress"))
```

## In progress

```dataview
TASK FROM "meridian"
WHERE !completed AND contains(text, "status::in-progress")
```
