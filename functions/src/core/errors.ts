/** Error carried to the HTTP layer as `{error: {code, message}}` with `status`. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export const invalid = (code: string, message: string): ApiError => new ApiError(400, code, message);
