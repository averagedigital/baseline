# Runtime assets and legacy Coach context

## Problem

Food detection assets were absent from the application bundle, while one incompatible local session payload could prevent a cloud Coach request.

## Symptoms

- Food detection reported `modelMissing` and nutrition reported `databaseMissing`.
- Coach displayed a local-data format error without sending the request.

## What did not work

Checking source paths alone did not prove that Xcode compiled and copied the resources into the built application.

## Root cause

`FoodDetector.mlmodel` and `nutrition.sqlite` were not project resources. Coach decoded the latest session strictly, so a legacy payload threw before the cloud call.

## Solution

Bundle the Core ML model and generated nutrition database. Build Coach facts only from compatible records, while preserving the current user request and other valid facts.

## Why it works

Xcode compiles the model to `FoodDetector.mlmodelc`; both loaders resolve their resources through `Bundle.main`. Legacy records no longer abort context assembly.

## Verification

Hosted iOS tests load both assets from the app bundle and reproduce the legacy-session case. The built `.app` is also inspected for both resources.

## Prevention

Keep hosted bundle-availability tests and a regression test containing an incompatible stored session payload.

## Applies when

An iOS runtime dependency is shipped as a bundle resource or persisted evidence schemas evolve across app versions.
