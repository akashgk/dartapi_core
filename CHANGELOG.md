## 0.0.7
- Add `pathParam<T>()` extension on `Request` for typed path parameter extraction
- Add `queryParam<T>()` extension on `Request` for typed query parameter extraction with optional default values
- Add `statusCode` field on `ApiRoute` (default `200`) for custom success response codes (e.g. 201, 204)
- Add `globalExceptionMiddleware` for app-level exception handling

## 0.0.6
- Add `ApiException` class for returning specific HTTP error status codes from handlers and validators
- Fix `FormatException` (malformed JSON body) now returns 400 Bad Request instead of 500
- Fix validation errors from `verifyKey()` now return 422 Unprocessable Entity instead of 500
- `ApiException` is exported from the package

## 0.0.5
- Improved Logging

## 0.0.4
- Improve code documentation

## 0.0.3
- Add Email Validator
## 0.0.2
- Change License
- Add Middelware
- Add Validators
- Enhance Key Verification with Validators

## 0.0.1
- Initial version.
