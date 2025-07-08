# CHANGELOG

## 0.3.2 (2025-07-03)

NEW FEATURES:
  * add `IAM_RETRY` argument to avoid API throttling (default:3)

## 0.3.1 (2021-03-16)

BUG FIXES:

* fix exception handling on IAM resources creation
* fix typos in CLI help

## 0.3.0 (2021-03-14)

NEW FEATURES:

* Better inline help
* Better error handling on CRUD operations

BUG FIXES:

* add missing default values
  - fix error on poorly formatted policy template
  - fix error on missing CR attributes
* fix missing error metrics

## 0.2.0 (2021-03-01)

NEW FEATURES:

* Implement Kubernetes ServiceAccount authentication
* Implement IRSA CLI installation for Cloudsap
  - `cloudsap install irsa ...`
* Implement Kubernetes CLI installation for Cloudsap
  - `cloudsap install full` ...
* Implement Kubernetes CRD installation for Cloudsap
  - `cloudsap install crd` ...
* Improved error handling
* Update README

BUG FIXES:

* fix missing/late logs
* fix Rack/Thin server binding
* fix missing CLI default

## 0.1.0 (2021-02-04)

* initial release
