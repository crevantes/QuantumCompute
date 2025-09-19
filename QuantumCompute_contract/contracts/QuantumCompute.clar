
;; title: QuantumCompute
;; version: 1.0.0
;; summary: Synthetic assets smart contract providing quantum computing industry and research exposure
;; description: This contract implements a synthetic asset token (qSTX) that tracks quantum computing
;;              industry performance, allowing users to gain exposure to quantum computing research
;;              and development without directly owning quantum computing companies or infrastructure.

;; traits
;; Implementing SIP-010 standard functions directly

;; token definitions
(define-fungible-token quantum-token)

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-paused (err u104))
(define-constant err-oracle-not-set (err u105))
(define-constant err-price-stale (err u106))

;; Token metadata
(define-constant token-name "QuantumCompute Synthetic Token")
(define-constant token-symbol "qSTX")
(define-constant token-decimals u6)
(define-constant token-uri u"https://quantumcompute.assets/metadata")

;; Economic parameters
(define-constant max-supply u1000000000000) ;; 1 million tokens with 6 decimals
(define-constant min-collateral-ratio u150) ;; 150% collateralization requirement

;; data vars
(define-data-var contract-paused bool false)
(define-data-var oracle-address (optional principal) none)
(define-data-var quantum-index-price uint u0)
(define-data-var last-price-update uint u0)
(define-data-var price-validity-period uint u144) ;; ~1 day in blocks
(define-data-var total-collateral uint u0)
(define-data-var collateral-ratio uint u150)
(define-data-var minting-fee uint u50) ;; 0.5% in basis points

;; data maps
(define-map authorized-minters principal bool)
(define-map authorized-oracles principal bool)
(define-map user-positions
    principal
    {
        collateral: uint,
        debt: uint,
        last-interaction: uint
    }
)

;; Quantum computing exposure tracking
(define-map quantum-metrics
    uint ;; timestamp (block-height)
    {
        research-funding: uint,
        patent-count: uint,
        market-cap: uint,
        breakthrough-score: uint
    }
)

;; public functions

;; SIP-010 Standard Functions
(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
    (begin
        (asserts! (not (var-get contract-paused)) err-paused)
        (asserts! (or (is-eq from tx-sender) (is-eq from contract-caller)) err-not-authorized)
        (ft-transfer? quantum-token amount from to)
    )
)

(define-public (get-name)
    (ok token-name)
)

(define-public (get-symbol)
    (ok token-symbol)
)

(define-public (get-decimals)
    (ok token-decimals)
)

(define-public (get-balance (who principal))
    (ok (ft-get-balance quantum-token who))
)

(define-public (get-total-supply)
    (ok (ft-get-supply quantum-token))
)

(define-public (get-token-uri)
    (ok (some token-uri))
)

;; Core Synthetic Asset Functions

;; Mint synthetic tokens with STX collateral
(define-public (mint-quantum-tokens (stx-amount uint) (quantum-tokens uint))
    (let (
        (current-price (var-get quantum-index-price))
        (required-collateral (/ (* quantum-tokens current-price (var-get collateral-ratio)) u100))
        (fee (/ (* quantum-tokens (var-get minting-fee)) u10000))
        (sender tx-sender)
        (current-position (default-to {collateral: u0, debt: u0, last-interaction: u0}
                                    (map-get? user-positions sender)))
    )
        (asserts! (not (var-get contract-paused)) err-paused)
        (asserts! (> quantum-tokens u0) err-invalid-amount)
        (asserts! (is-price-fresh) err-price-stale)
        (asserts! (>= stx-amount required-collateral) err-insufficient-balance)

        ;; Transfer STX collateral to contract
        (try! (stx-transfer? stx-amount sender (as-contract tx-sender)))

        ;; Mint quantum tokens
        (try! (ft-mint? quantum-token quantum-tokens sender))

        ;; Update user position
        (map-set user-positions sender {
            collateral: (+ (get collateral current-position) stx-amount),
            debt: (+ (get debt current-position) quantum-tokens),
            last-interaction: block-height
        })

        ;; Update total collateral
        (var-set total-collateral (+ (var-get total-collateral) stx-amount))

        (ok {minted: quantum-tokens, collateral-added: stx-amount, fee: fee})
    )
)

;; Burn synthetic tokens and reclaim collateral
(define-public (burn-quantum-tokens (quantum-tokens uint))
    (let (
        (sender tx-sender)
        (current-position (unwrap! (map-get? user-positions sender) err-insufficient-balance))
        (current-price (var-get quantum-index-price))
        (collateral-to-return (/ (* quantum-tokens (get collateral current-position)) (get debt current-position)))
    )
        (asserts! (not (var-get contract-paused)) err-paused)
        (asserts! (> quantum-tokens u0) err-invalid-amount)
        (asserts! (>= (get debt current-position) quantum-tokens) err-insufficient-balance)
        (asserts! (is-price-fresh) err-price-stale)

        ;; Burn quantum tokens
        (try! (ft-burn? quantum-token quantum-tokens sender))

        ;; Return proportional STX collateral
        (try! (as-contract (stx-transfer? collateral-to-return tx-sender sender)))

        ;; Update user position
        (map-set user-positions sender {
            collateral: (- (get collateral current-position) collateral-to-return),
            debt: (- (get debt current-position) quantum-tokens),
            last-interaction: block-height
        })

        ;; Update total collateral
        (var-set total-collateral (- (var-get total-collateral) collateral-to-return))

        (ok {burned: quantum-tokens, collateral-returned: collateral-to-return})
    )
)

;; Oracle and Price Management

;; Update quantum computing index price (oracle only)
(define-public (update-quantum-price (new-price uint) (research-funding uint) (patent-count uint) (market-cap uint) (breakthrough-score uint))
    (begin
        (asserts! (is-authorized-oracle tx-sender) err-not-authorized)
        (asserts! (> new-price u0) err-invalid-amount)

        ;; Update price and metrics
        (var-set quantum-index-price new-price)
        (var-set last-price-update block-height)

        ;; Store quantum metrics for transparency
        (map-set quantum-metrics block-height {
            research-funding: research-funding,
            patent-count: patent-count,
            market-cap: market-cap,
            breakthrough-score: breakthrough-score
        })

        (ok new-price)
    )
)

;; Administrative Functions

;; Set oracle address (owner only)
(define-public (set-oracle (oracle principal) (authorized bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set authorized-oracles oracle authorized)
        (if authorized
            (var-set oracle-address (some oracle))
            (var-set oracle-address none)
        )
        (ok authorized)
    )
)

;; Authorize minter (owner only)
(define-public (set-minter-authorization (minter principal) (authorized bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set authorized-minters minter authorized)
        (ok authorized)
    )
)

;; Emergency pause (owner only)
(define-public (toggle-pause)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-paused (not (var-get contract-paused)))
        (ok (var-get contract-paused))
    )
)

;; Update economic parameters (owner only)
(define-public (update-parameters (new-collateral-ratio uint) (new-minting-fee uint) (new-price-validity uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (>= new-collateral-ratio u100) err-invalid-amount) ;; Min 100%
        (asserts! (<= new-minting-fee u1000) err-invalid-amount) ;; Max 10%

        (var-set collateral-ratio new-collateral-ratio)
        (var-set minting-fee new-minting-fee)
        (var-set price-validity-period new-price-validity)

        (ok true)
    )
)

;; read only functions

;; Check if price is fresh
(define-read-only (is-price-fresh)
    (<= (- block-height (var-get last-price-update)) (var-get price-validity-period))
)

;; Check if principal is authorized oracle
(define-read-only (is-authorized-oracle (principal principal))
    (default-to false (map-get? authorized-oracles principal))
)

;; Check if principal is authorized minter
(define-read-only (is-authorized-minter (principal principal))
    (default-to false (map-get? authorized-minters principal))
)

;; Get current quantum metrics
(define-read-only (get-quantum-metrics (timestamp uint))
    (map-get? quantum-metrics timestamp)
)

;; Get user position
(define-read-only (get-user-position (user principal))
    (map-get? user-positions user)
)

;; Calculate collateralization ratio for user
(define-read-only (get-user-collateral-ratio (user principal))
    (match (map-get? user-positions user)
        position (if (> (get debt position) u0)
                    (some (/ (* (get collateral position) u100)
                           (* (get debt position) (var-get quantum-index-price))))
                    (some u0))
        none
    )
)

;; Get contract status
(define-read-only (get-contract-info)
    {
        paused: (var-get contract-paused),
        total-supply: (ft-get-supply quantum-token),
        total-collateral: (var-get total-collateral),
        current-price: (var-get quantum-index-price),
        last-price-update: (var-get last-price-update),
        collateral-ratio: (var-get collateral-ratio),
        minting-fee: (var-get minting-fee)
    }
)

;; Calculate required collateral for minting
(define-read-only (calculate-collateral-requirement (quantum-tokens uint))
    (/ (* quantum-tokens (var-get quantum-index-price) (var-get collateral-ratio)) u100)
)

;; private functions

;; Initialize contract with default oracle (called once)
(define-private (initialize)
    (begin
        (map-set authorized-oracles contract-owner true)
        (var-set quantum-index-price u1000000) ;; Initial price: 1 STX per token
        (var-set last-price-update block-height)
        true
    )
)

;; Contract initialization
(initialize)
