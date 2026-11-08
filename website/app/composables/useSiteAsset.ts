export function useSiteAsset(path: string) {
  return useRuntimeConfig().app.baseURL + path.replace(/^\//, '')
}
