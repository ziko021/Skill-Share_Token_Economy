;; Skill-Share Token Economy Smart Contract
;; Exchange skills and services using time-based tokens

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-service-not-found (err u104))
(define-constant err-booking-not-found (err u105))
(define-constant err-service-unavailable (err u106))
(define-constant err-already-completed (err u107))
(define-constant err-unauthorized (err u108))
(define-constant err-invalid-rating (err u109))

;; Data Variables
(define-data-var total-supply uint u0)
(define-data-var next-service-id uint u1)
(define-data-var next-booking-id uint u1)

;; Token balances (principal -> time-tokens in minutes)
(define-map token-balances principal uint)

;; User profiles
(define-map user-profiles 
  principal 
  {
    username: (string-ascii 50),
    reputation-score: uint,
    total-hours-provided: uint,
    total-hours-consumed: uint,
    join-date: uint
  }
)

;; Services offered
(define-map services
  uint
  {
    provider: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    category: (string-ascii 50),
    rate-per-hour: uint,
    is-active: bool,
    created-at: uint
  }
)

;; Service bookings
(define-map bookings
  uint
  {
    service-id: uint,
    client: principal,
    provider: principal,
    duration-minutes: uint,
    total-cost: uint,
    status: (string-ascii 20),
    created-at: uint,
    completed-at: (optional uint),
    client-rating: (optional uint),
    provider-rating: (optional uint)
  }
)

;; Provider categories and skills
(define-map provider-skills principal (list 10 (string-ascii 50)))

;; Read-only functions

(define-read-only (get-balance (account principal))
  (default-to u0 (map-get? token-balances account))
)

(define-read-only (get-total-supply)
  (var-get total-supply)
)

(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles user)
)

(define-read-only (get-service (service-id uint))
  (map-get? services service-id)
)

(define-read-only (get-booking (booking-id uint))
  (map-get? bookings booking-id)
)

(define-read-only (get-provider-skills (provider principal))
  (default-to (list) (map-get? provider-skills provider))
)

;; Public functions

;; Initialize user profile
(define-public (create-profile (username (string-ascii 50)) (skills (list 10 (string-ascii 50))))
  (begin
    (map-set user-profiles tx-sender {
      username: username,
      reputation-score: u100,
      total-hours-provided: u0,
      total-hours-consumed: u0,
      join-date: block-height
    })
    (map-set provider-skills tx-sender skills)
    (ok true)
  )
)

;; Mint initial tokens (owner only for bootstrapping)
(define-public (mint-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (let 
      (
        (current-balance (get-balance recipient))
        (new-balance (+ current-balance amount))
        (new-supply (+ (var-get total-supply) amount))
      )
      (map-set token-balances recipient new-balance)
      (var-set total-supply new-supply)
      (ok new-balance)
    )
  )
)

;; Transfer tokens between users
(define-public (transfer (amount uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) err-not-token-owner)
    (asserts! (> amount u0) err-invalid-amount)
    (let
      (
        (sender-balance (get-balance sender))
        (recipient-balance (get-balance recipient))
      )
      (asserts! (>= sender-balance amount) err-insufficient-balance)
      (map-set token-balances sender (- sender-balance amount))
      (map-set token-balances recipient (+ recipient-balance amount))
      (ok true)
    )
  )
)

;; Create a service offering
(define-public (create-service 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (category (string-ascii 50))
  (rate-per-hour uint)
)
  (let
    (
      (service-id (var-get next-service-id))
    )
    (map-set services service-id {
      provider: tx-sender,
      title: title,
      description: description,
      category: category,
      rate-per-hour: rate-per-hour,
      is-active: true,
      created-at: block-height
    })
    (var-set next-service-id (+ service-id u1))
    (ok service-id)
  )
)

;; Update service status
(define-public (toggle-service-status (service-id uint))
  (let
    (
      (service (unwrap! (map-get? services service-id) err-service-not-found))
    )
    (asserts! (is-eq tx-sender (get provider service)) err-unauthorized)
    (map-set services service-id 
      (merge service { is-active: (not (get is-active service)) })
    )
    (ok true)
  )
)

;; Book a service
(define-public (book-service (service-id uint) (duration-minutes uint))
  (let
    (
      (service (unwrap! (map-get? services service-id) err-service-not-found))
      (booking-id (var-get next-booking-id))
      (cost-per-minute (/ (get rate-per-hour service) u60))
      (total-cost (* duration-minutes cost-per-minute))
      (client-balance (get-balance tx-sender))
    )
    (asserts! (get is-active service) err-service-unavailable)
    (asserts! (>= client-balance total-cost) err-insufficient-balance)
    (asserts! (> duration-minutes u0) err-invalid-amount)
    
    ;; Create booking
    (map-set bookings booking-id {
      service-id: service-id,
      client: tx-sender,
      provider: (get provider service),
      duration-minutes: duration-minutes,
      total-cost: total-cost,
      status: "pending",
      created-at: block-height,
      completed-at: none,
      client-rating: none,
      provider-rating: none
    })
    
    ;; Hold tokens (escrow)
    (map-set token-balances tx-sender (- client-balance total-cost))
    
    (var-set next-booking-id (+ booking-id u1))
    (ok booking-id)
  )
)

;; Complete a service (provider confirms completion)
(define-public (complete-service (booking-id uint))
  (let
    (
      (booking (unwrap! (map-get? bookings booking-id) err-booking-not-found))
    )
    (asserts! (is-eq tx-sender (get provider booking)) err-unauthorized)
    (asserts! (is-eq (get status booking) "pending") err-already-completed)
    
    ;; Transfer tokens from escrow to provider
    (let
      (
        (provider-balance (get-balance (get provider booking)))
        (new-provider-balance (+ provider-balance (get total-cost booking)))
      )
      (map-set token-balances (get provider booking) new-provider-balance)
      
      ;; Update booking status
      (map-set bookings booking-id 
        (merge booking {
          status: "completed",
          completed-at: (some block-height)
        })
      )
      
      ;; Update provider stats
      (match (map-get? user-profiles (get provider booking))
        profile (map-set user-profiles (get provider booking)
          (merge profile {
            total-hours-provided: (+ (get total-hours-provided profile) 
                                   (/ (get duration-minutes booking) u60))
          })
        )
        true
      )
      
      ;; Update client stats
      (match (map-get? user-profiles (get client booking))
        profile (map-set user-profiles (get client booking)
          (merge profile {
            total-hours-consumed: (+ (get total-hours-consumed profile) 
                                   (/ (get duration-minutes booking) u60))
          })
        )
        true
      )
      
      (ok true)
    )
  )
)

;; Rate a completed service
(define-public (rate-service (booking-id uint) (rating uint) (is-client bool))
  (let
    (
      (booking (unwrap! (map-get? bookings booking-id) err-booking-not-found))
    )
    (asserts! (>= rating u1) err-invalid-rating)
    (asserts! (<= rating u5) err-invalid-rating)
    (asserts! (is-eq (get status booking) "completed") err-unauthorized)
    
    (if is-client
      (begin
        (asserts! (is-eq tx-sender (get client booking)) err-unauthorized)
        (map-set bookings booking-id 
          (merge booking { client-rating: (some rating) })
        )
      )
      (begin
        (asserts! (is-eq tx-sender (get provider booking)) err-unauthorized)
        (map-set bookings booking-id 
          (merge booking { provider-rating: (some rating) })
        )
      )
    )
    (ok true)
  )
)

;; Earn tokens by providing time/work (simplified time-banking mechanism)
(define-public (earn-time-tokens (minutes-worked uint) (work-description (string-ascii 200)))
  (begin
    (asserts! (> minutes-worked u0) err-invalid-amount)
    (let
      (
        (current-balance (get-balance tx-sender))
        (new-balance (+ current-balance minutes-worked))
        (new-supply (+ (var-get total-supply) minutes-worked))
      )
      (map-set token-balances tx-sender new-balance)
      (var-set total-supply new-supply)
      (ok new-balance)
    )
  )
)

;; Cancel pending booking (before completion)
(define-public (cancel-booking (booking-id uint))
  (let
    (
      (booking (unwrap! (map-get? bookings booking-id) err-booking-not-found))
    )
    (asserts! (is-eq tx-sender (get client booking)) err-unauthorized)
    (asserts! (is-eq (get status booking) "pending") err-already-completed)
    
    ;; Refund tokens to client
    (let
      (
        (client-balance (get-balance (get client booking)))
        (refund-amount (get total-cost booking))
      )
      (map-set token-balances (get client booking) (+ client-balance refund-amount))
      
      ;; Update booking status
      (map-set bookings booking-id 
        (merge booking { status: "cancelled" })
      )
      
      (ok true)
    )
  )
)