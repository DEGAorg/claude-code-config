
# UnifiedEvent

A grouped collection of related markets (e.g., \"Who will be Fed Chair?\" contains multiple candidate markets)

## Properties

Name | Type
------------ | -------------
`id` | string
`title` | string
`description` | string
`slug` | string
`markets` | [Array&lt;UnifiedMarket&gt;](UnifiedMarket.md)
`url` | string
`image` | string
`category` | string
`tags` | Array&lt;string&gt;

## Example

```typescript
import type { UnifiedEvent } from 'pmxtjs'

// TODO: Update the object below with actual values
const example = {
  "id": null,
  "title": null,
  "description": null,
  "slug": null,
  "markets": null,
  "url": null,
  "image": null,
  "category": null,
  "tags": null,
} satisfies UnifiedEvent

console.log(example)

// Convert the instance to a JSON string
const exampleJSON: string = JSON.stringify(example)
console.log(exampleJSON)

// Parse the JSON string back to an object
const exampleParsed = JSON.parse(exampleJSON) as UnifiedEvent
console.log(exampleParsed)
```

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)


