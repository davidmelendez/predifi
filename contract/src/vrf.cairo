use starknet::ContractAddress;

#[starknet::interface]
trait IExampleRandomness<TContractState> {
    fn get_last_random(self: @TContractState) -> felt252;
    fn request_my_randomness(
        ref self: TContractState,
        seed: u64,
        callback_address: ContractAddress,
        callback_fee_limit: u128,
        publish_delay: u64,
        num_words: u64,
        calldata: Array<felt252>,
    );
    fn receive_random_words(
        ref self: TContractState,
        requestor_address: ContractAddress,
        request_id: u64,
        random_words: Span<felt252>,
        calldata: Array<felt252>,
    );
    // fn withdraw_funds(ref self: TContractState, receiver: ContractAddress);
}

#[starknet::contract]
pub mod ExampleRandomness {
    use starknet::storage::StoragePointerReadAccess;
    use starknet::storage::StoragePointerWriteAccess;
    use super::{ContractAddress, IExampleRandomness};
    use starknet::{get_block_number, get_caller_address, get_contract_address};
    use pragma_lib::abi::{IRandomnessDispatcher, IRandomnessDispatcherTrait};
    use core::array::{ArrayTrait, SpanTrait};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use core::traits::{TryInto, Into};

    #[storage]
    struct Storage {
        randomness_contract_address: ContractAddress,
        min_block_number_storage: u64,
        last_random_storage: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, randomness_contract_address: ContractAddress) {
        self.randomness_contract_address.write(randomness_contract_address);
    }

    #[abi(embed_v0)]
    impl IExampleRandomnessImpl of IExampleRandomness<ContractState> {
        fn get_last_random(self: @ContractState) -> felt252 {
            let last_random = self.last_random_storage.read();
            return last_random;
        }

        fn request_my_randomness(
            ref self: ContractState,
            seed: u64,
            callback_address: ContractAddress,
            callback_fee_limit: u128,
            publish_delay: u64,
            num_words: u64,
            calldata: Array<felt252>,
        ) {
            let randomness_contract_address = self.randomness_contract_address.read();
            let randomness_dispatcher = IRandomnessDispatcher {
                contract_address: randomness_contract_address,
            };
            let caller = get_caller_address();
            let compute_fees = randomness_dispatcher.compute_premium_fee(caller);

            // Approve the randomness contract to transfer the callback fee
            // You would need to send some ETH to this contract first to cover the fees
            let eth_dispatcher = IERC20Dispatcher {
                contract_address: 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 // ETH Contract Address
                    .try_into()
                    .unwrap(),
            };
            eth_dispatcher
                .approve(
                    randomness_contract_address,
                    (callback_fee_limit + compute_fees + callback_fee_limit / 5).into(),
                );

            // Request the randomness
            randomness_dispatcher
                .request_random(
                    seed, callback_address, callback_fee_limit, publish_delay, num_words, calldata,
                );

            let current_block_number = get_block_number();
            self.min_block_number_storage.write(current_block_number + publish_delay);
            // return request_id;

        }

        fn receive_random_words(
            ref self: ContractState,
            requestor_address: ContractAddress,
            request_id: u64,
            random_words: Span<felt252>,
            calldata: Array<felt252>,
        ) {
            // Have to make sure that the caller is the Pragma Randomness Oracle contract
            let caller_address = get_caller_address();
            assert(
                caller_address == self.randomness_contract_address.read(),
                'caller not randomness contract',
            );
            // and that the current block is within publish_delay of the request block
            let current_block_number = get_block_number();
            let min_block_number = self.min_block_number_storage.read();
            assert(min_block_number <= current_block_number, 'block number issue');

            // Verify that the requestor_address is the contract itself
            let contract_address = get_contract_address();
            assert(requestor_address == contract_address, 'requestor is not self');

            // Make sure random_words has the expected length
            let random_words_len = random_words.len();
            assert(random_words_len > 0_u32, 'no random words provided');

            // Your code using randomness!
            let random_word = *random_words.at(0);

            self.last_random_storage.write(random_word);

            return ();
        }
    }
}
