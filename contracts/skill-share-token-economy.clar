;; Skill-Share Token Economy Smart Contract
;; A decentralized platform for exchanging skills and services using time-based tokens

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_SERVICE_NOT_FOUND (err u103))
(define-constant ERR_BOOKING_NOT_FOUND (err u104))
(define-constant ERR_ALREADY_COMPLETED (err u105))
(define-constant ERR_INVALID_STATUS (err u106))
(define-constant ERR_SELF_BOOKING (err u107))
(define-constant ERR_INVALID_RATING (err u108))

;; Token name and symbol
(define-fungible-token skill-time-token)
(define-constant TOKEN_NAME "SkillTime")
(define-constant TOKEN_SYMBOL "STT")

;; Data Variables
(define-data-var total-supply uint u0)
(define-data-var service-id-nonce uint u0)
(define-data-var booking-id-nonce uint u0)

;; Data Maps
(define-map balances principal uint)
(define-map user-profiles principal {
    name: (string-ascii 50),
    skills: (list 10 (string-ascii 30)),
    reputation-score: uint,
    total-services: uint,
    total-bookings: uint
})

(define-map services uint {
    provider: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    category: (string-ascii 30),
    rate-per-hour: uint,
    available: bool,
    created-at: uint
})

(define-map bookings uint {
    service-id: uint,
    provider: principal,
    client: principal,
    hours: uint,
    total-tokens: uint,
    status: (string-ascii 20),
    created-at: uint,
    completed-at: (optional uint),
    rating: (optional uint)
})

(define-map user-earnings principal uint)
(define-map escrow-balances uint uint)

;; Token Functions
(define-public (mint-tokens (recipient principal) (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (try! (ft-mint? skill-time-token amount recipient))
        (var-set total-supply (+ (var-get total-supply) amount))
        (map-set balances recipient (+ (default-to u0 (map-get? balances recipient)) amount))
        (ok amount)
    )
)

(define-public (transfer-tokens (recipient principal) (amount uint))
    (begin
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= (get-balance tx-sender) amount) ERR_INSUFFICIENT_BALANCE)
        (try! (ft-transfer? skill-time-token amount tx-sender recipient))
        (map-set balances tx-sender (- (get-balance tx-sender) amount))
        (map-set balances recipient (+ (get-balance recipient) amount))
        (ok amount)
    )
)

;; Profile Management
(define-public (create-profile (name (string-ascii 50)) (skills (list 10 (string-ascii 30))))
    (begin
        (map-set user-profiles tx-sender {
            name: name,
            skills: skills,
            reputation-score: u0,
            total-services: u0,
            total-bookings: u0
        })
        (ok true)
    )
)

(define-public (update-skills (skills (list 10 (string-ascii 30))))
    (let ((profile (unwrap! (map-get? user-profiles tx-sender) ERR_UNAUTHORIZED)))
        (map-set user-profiles tx-sender (merge profile { skills: skills }))
        (ok true)
    )
)

;; Service Management
(define-public (create-service (title (string-ascii 100)) 
                              (description (string-ascii 500))
                              (category (string-ascii 30))
                              (rate-per-hour uint))
    (let ((service-id (+ (var-get service-id-nonce) u1)))
        (asserts! (> rate-per-hour u0) ERR_INVALID_AMOUNT)
        (map-set services service-id {
            provider: tx-sender,
            title: title,
            description: description,
            category: category,
            rate-per-hour: rate-per-hour,
            available: true,
            created-at: block-height
        })
        (var-set service-id-nonce service-id)
        (let ((profile (default-to { name: "", skills: (list), reputation-score: u0, total-services: u0, total-bookings: u0 } 
                                   (map-get? user-profiles tx-sender))))
            (map-set user-profiles tx-sender 
                (merge profile { total-services: (+ (get total-services profile) u1) }))
        )
        (ok service-id)
    )
)

(define-public (toggle-service-availability (service-id uint))
    (let ((service (unwrap! (map-get? services service-id) ERR_SERVICE_NOT_FOUND)))
        (asserts! (is-eq (get provider service) tx-sender) ERR_UNAUTHORIZED)
        (map-set services service-id (merge service { available: (not (get available service)) }))
        (ok true)
    )
)

;; Booking System
(define-public (book-service (service-id uint) (hours uint))
    (let ((service (unwrap! (map-get? services service-id) ERR_SERVICE_NOT_FOUND))
          (booking-id (+ (var-get booking-id-nonce) u1))
          (total-cost (* hours (get rate-per-hour service))))
        (asserts! (get available service) ERR_INVALID_STATUS)
        (asserts! (> hours u0) ERR_INVALID_AMOUNT)
        (asserts! (not (is-eq tx-sender (get provider service))) ERR_SELF_BOOKING)
        (asserts! (>= (get-balance tx-sender) total-cost) ERR_INSUFFICIENT_BALANCE)
        
        ;; Transfer tokens to escrow
        (try! (ft-transfer? skill-time-token total-cost tx-sender (as-contract tx-sender)))
        (map-set balances tx-sender (- (get-balance tx-sender) total-cost))
        (map-set escrow-balances booking-id total-cost)
        
        ;; Create booking
        (map-set bookings booking-id {
            service-id: service-id,
            provider: (get provider service),
            client: tx-sender,
            hours: hours,
            total-tokens: total-cost,
            status: "pending",
            created-at: block-height,
            completed-at: none,
            rating: none
        })
        (var-set booking-id-nonce booking-id)
        
        ;; Update client profile
        (let ((profile (default-to { name: "", skills: (list), reputation-score: u0, total-services: u0, total-bookings: u0 } 
                                   (map-get? user-profiles tx-sender))))
            (map-set user-profiles tx-sender 
                (merge profile { total-bookings: (+ (get total-bookings profile) u1) }))
        )
        (ok booking-id)
    )
)

(define-public (complete-service (booking-id uint))
    (let ((booking (unwrap! (map-get? bookings booking-id) ERR_BOOKING_NOT_FOUND)))
        (asserts! (is-eq (get provider booking) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status booking) "pending") ERR_ALREADY_COMPLETED)
        
        ;; Release tokens from escrow to provider
        (let ((escrow-amount (unwrap! (map-get? escrow-balances booking-id) ERR_BOOKING_NOT_FOUND)))
            (try! (as-contract (ft-transfer? skill-time-token escrow-amount tx-sender (get provider booking))))
            (map-set balances (get provider booking) (+ (get-balance (get provider booking)) escrow-amount))
            (map-set user-earnings (get provider booking) 
                (+ (default-to u0 (map-get? user-earnings (get provider booking))) escrow-amount))
            (map-delete escrow-balances booking-id)
        )
        
        ;; Update booking status
        (map-set bookings booking-id (merge booking { 
            status: "completed",
            completed-at: (some block-height)
        }))
        (ok true)
    )
)

(define-public (rate-service (booking-id uint) (rating uint))
    (let ((booking (unwrap! (map-get? bookings booking-id) ERR_BOOKING_NOT_FOUND)))
        (asserts! (is-eq (get client booking) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status booking) "completed") ERR_INVALID_STATUS)
        (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_RATING)
        
        ;; Update booking with rating
        (map-set bookings booking-id (merge booking { rating: (some rating) }))
        
        ;; Update provider's reputation
        (let ((provider-profile (default-to { name: "", skills: (list), reputation-score: u0, total-services: u0, total-bookings: u0 } 
                                           (map-get? user-profiles (get provider booking)))))
            (let ((current-score (get reputation-score provider-profile))
                  (total-services (get total-services provider-profile)))
                (if (is-eq total-services u0)
                    (map-set user-profiles (get provider booking) 
                        (merge provider-profile { reputation-score: rating }))
                    (map-set user-profiles (get provider booking) 
                        (merge provider-profile { reputation-score: (/ (+ (* current-score total-services) rating) (+ total-services u1)) }))
                )
            )
        )
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-balance (account principal))
    (default-to u0 (map-get? balances account))
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

(define-read-only (get-user-earnings (user principal))
    (default-to u0 (map-get? user-earnings user))
)

(define-read-only (get-service-count)
    (var-get service-id-nonce)
)

(define-read-only (get-booking-count)
    (var-get booking-id-nonce)
)

;; Token trait implementations
(define-read-only (get-name)
    (ok TOKEN_NAME)
)

(define-read-only (get-symbol)
    (ok TOKEN_SYMBOL)
)

(define-read-only (get-decimals)
    (ok u0)
)

(define-read-only (get-token-uri)
    (ok none)
)

;; Initialize contract
(begin
    (try! (ft-mint? skill-time-token u1000000 CONTRACT_OWNER))
    (var-set total-supply u1000000)
    (map-set balances CONTRACT_OWNER u1000000)
)